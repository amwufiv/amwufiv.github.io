---
layout: post
title:  "spark调优1-节点动态伸缩"
date:   2022-09-17 17:18:00 +0800
categories: spark
tags:
- spark
---
## 现象
前几天同事反馈有个任务执行时间特别长，跑了几个小时还没出来。看了下 SQL 逻辑发现很简单只是查询过滤了几个上报埋点做 group by sum，实例却一直跑不出来。

将 SQL 复制出来执行同样特别慢。到 ui 界面查看执行情况，发现一开始有 1000 多个executor 但执行完几百个 task 后 executor 开始慢慢被 killed，最后活跃的 executor 掉到个位数。只有几个节点在计算几万个 task 的 stage，难怪会一直跑不出来。
![ui](https://github.com/amwufiv/img_host/raw/master/blog/spark-practice-1-1.39daz1ozvtc0.png)

## 排查过程
首先从被杀掉的节点查询日志，发现都是在执行完任务 20 - 30s 后被 kill，有些甚至任务都没执行就终止了。
![kill log](https://github.com/amwufiv/img_host/raw/master/blog/spark-practice-1-3.7dpzq5sj1wc0.png)

再看 driver 日志，发现里面也有记录节点被 kill 日志。
![driver log](https://github.com/amwufiv/img_host/raw/master/blog/spark-practice-1-2.6hd9f5zk9n40.png)
`ExecutorAllocationManager` 打印的日志，因为我们的集群是默认开启动态伸缩的，看 `spark.dynamicAllocation.executorIdleTimeout` 执行节点超时时间的配置项值确实是 20s。所以问题是 1000 多个 executor 为什么刚创建出来闲置了 20s 而没有分配到任务呢。先尝试把闲置超时配置项改为 600s，重新执行验证确实正常执行了，监控分配启动了 1000 多个 executor 在执行。但遗留了两个问题：
1. 为什么闲置的节点没有分配到任务？
2. 节点是动态伸缩的，闲置的节点被杀掉后为何没有再动态扩容，总共还有 5 万多个 task 嗷嗷待哺呢？

## 程序执行逻辑
我们可以看下 spark 代码的执行逻辑。可以看到有一个 `ExecutorAllocationManager` 专门负责执行节点的调整，具体是注册了 listener 监听 stage 和 task 的执行、监听 executor 的变化，并派生一个守护线程定时计算是否需要了增加执行节点，清理闲置节点也在守护进程中执行。首先 manager 有一个变量 `numExecutorsTarget` 专门记录累计申请的节点数据，初始值为 `spark.dynamicAllocation.initialExecutors`，定时任务会先计算等待执行和正在执行的任务数（这里默认一个节点设置 1 个核心），如果等待执行任务数 > `numExecutorsTarget` 那以前一轮申请的节点数＊2 向集群申请新执行节点，第一轮申请节点数为 1，直到 `numExecutorsTarget = spark.dynamicAllocation.maxExecutors`。

**这里的问题是当 `numExecutorsTarget` 达到最大时就不会再去向 yarn 发起资源请求，即使之前申请过的节点被杀掉了，这就是闲置的节点被杀掉后没有扩容的原因。**


再看任务分配的逻辑，spark 由 `TaskScheduleImpl` 来分配任务，又是调用 `TaskSetManager#resourceOffer` 来实现。可以理解具体的任务分配逻辑是这样的：
1. 将所有可用 executor shuffle 打乱并挨个调用 `resourceOffer` 方法来分配任务。
2. 某个 executor 是否能分配到任务最主要的影响因素就是待执行任务的 locality 优先级，优先按任务的 locality 优先级分配，依次为 `PROCESS_LOCAL -> NODE_LOCAL -> NO_PREF -> RACK_LOCAL -> ANY`。**优先级高的任务都分配完才会分配下一个优先级的任务。**
3. locality 优先级也不是绝对一定要分配完任务才降级，因为存在某些场景如 node_local 的节点失败太多被列入黑名单都分配不了，taskManager 分配任务的时间超过了`spark.locality.wait.node`还是会临时降级给 executor 分配 rack_local 任务。

那么我们回头看下之前失败任务 driver 的日志，会发现在节点被 killed 前，taskManager 一直在分配 node_local 任务给其它节点，有任务被分配那最后一个分配时间也会一直刷新，也就不会超过`spark.locality.wait.node`，导致没有 node_local 任务执行节点一直闲置获取不到任务，最后被杀掉。

任务的优先级是如何定义的？
添加任务时会把任务做归类，如果一个任务数据的 host 也有执行的 executor 在跑那这个任务会被加到 node_pending_tasks 队列。因为集群没有机架信息，所以实际任务默认会添加到 rack_local_pending_tasks 队列。

## 优化
根据上面分析的原因，我们可以优化的配置项有：
1. 将闲置超时时间改长 `set spark.dynamicAllocation.executorIdleTimeout=600s`;
2. 将读取同节点数据的超时时间设置为0 `set spark.locality.wait.node=0`;

但如上面所说，如果修改闲置时间过长，因为 spark task 分配优先级的机制，在 node_local tasks 跑完前虽然节点没有被杀掉但大部分基本处于闲置状态，浪费集群资源。

实际测试发现，如果跳过 node_local 的分配优先级执行时间会更快，基本所有的节点都能够立即获取任务并执行。虽然跨机器读取数据会有网络延迟及带宽限制，但在今天几十T的数据都能在百ms内跨过太平洋到达西海岸，何况是内部的计算集群。实际看执行日志读取一个 rack_local 的任务数据并计算完成也只花了 2s。

## 结果
修改配置后基本 10min 跑完任务。

