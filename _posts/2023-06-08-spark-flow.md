---
layout: post
title:  "spark执行流程"
date:   2023-06-08 15:18:00 +0800
categories: spark
tags:
- spark
---
## 执行主流程
![spark flow](https://github.com/amwufiv/img_host/raw/master/blog/spark-flow.4b81ofynias0.png)

当 SQL 任务提交后，parser 会把 SQL 解析成 LogicalPlan，经过 Analyzer、Optimizer 和其它规则分析优化后得到执行计算 executePlan，调用 `queryExecuton.execute()`方法会得到 final rdd。当执行 rdd action 操作时，才开始提交 job 给 DAGScheduler， scheduler 按照 rdd llineage 将 job 拆分成stagte 并根据依赖顺序提交，在 submitStage 阶段又会生成具体执行的 tasks，并成生一个新的 taskManager 管理，当 backend 需要新的任务时，taskManager 负责分配 task 给 executor（只分配不分发

## 生成逻辑执行计划
当任务提交后，SQL 通过 parser 得到 LogicalPlan，但这只是逻辑上的计划，它是未经校验的，缺少表字段元数据。Analyzer 会对 LogicalPlan 做遍历，分析规则很多，具体可细看 `org.apache.spark.sql.catalyst.analysis.Analyzer` 的代码，下面举几个例子
- CTESubstitution
> 将所有 with clause 表别名在 SQL 的引用替换成实际的查询，纯粹的替换，对性能的优化为 0。（起码在 spark 2.x 中，对于复杂查询，不应该把复杂子查询直接写成 CTE 在 SQL 中多处引用）
- ResolveFunctions
> 校验函数是否存在，并将函数引用解析成对应的函数表达式
- TypeCoercion.typeCoercionRules
> 类型的隐式转换，在前面的文章中也有介绍

## 生成物理执行计划
### 优化
得到分析后的 LogicalPlan 后，`SparkOptimizer` 会对其进行优化，和 Analyzer 一样也会应用多个规则，具体可细看 `org.apache.spark.sql.execution.SparkOptimizer` 的代码，下面举几个例子
- RewriteDistinctAggregates
> 消除 distinct：以「distinct 字段 + 分组字段」为 key 拆分出多个 group by，不同 key 和非 distinct 查询字段会生成不同的 gid，再 expand 出多份对应 gid 的数据。SQL 中不同字段的 distinct 越多，expand 出来的数据翻的倍数越多（这里可能有性能问题）
- PushProjectionThroughUnion
> 将字段查询下推给 UNION ALL 子查询
- RewritePredicateSubquery
> 将 exists / in 条件中的子查询转化为 left semi join（not exists / not in 则转化为 left anti join）

最终得到优化后的 LogicalPlan。

### 转换成 executePlan
优化后的 LogicalPlan 最后经过 `SparkPlanner` 的 strategies（将各类型的 plan 转成对应的 exec）处理，得到可执行的 SparkPlan。以 group by SQL 为例，`select column from table` 会映射成 Project，group by 聚合会生成 Aggregate；因为 SQL 中用的是支持部分聚合的函数 sum、max，所以会有两个 Aggregate——先在分区内做局部聚合减少数据量，再 Exchange shuffle 后执行一次最终聚合。

<!-- TODO: 补 group by 的 executePlan 截图 -->

spark 任务启动时执行计划也会打印在 driver 日志中，有时可以据此判断开发的 SQL 是否合理。

## 生成 RDD
得到 SparkPlan 后，调用 `execute()` 即可执行并生成 RDD。大概逻辑是：最底层的 TableScan 转化为最原始的 ScanRDD，每个上层计划在子 RDD 的基础上执行操作（如 `mapPartitions(mapFunc)`）产生新的 RDD，如此 transform up 得到最终的 RDD。

<!-- TODO: explain codegen & shuffle exchange -->

## 生成 Stage
最终 RDD 在调用 action 方法时，会向 DAGScheduler 提交 job，scheduler 根据 final RDD 的血缘（lineage）和 partition 依赖，追溯并划分不同的 stage。当子 RDD 与父 RDD 之间的依赖是 ShuffleDependency 时，子 RDD 就要拆分出新的 stage。

## 生成 Tasks
提交 stage 时会同时生成该 stage 的 tasks 并向 taskScheduler 提交，同时广播任务执行代码。创建 task 时会附带 RDD partition 的 locs 信息，为之后按 locality 优先级分配任务提供依据；locs 由每个 RDD 的 `getPreferredLocations` 计算得到。

## Tasks 分配
tasks 的分配在之前的文章中已有描述，这里不再展开。