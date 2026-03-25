---
layout: post
title:  "spark调优2-类型隐式转换"
date:   2023-02-15 15:18:00 +0800
categories: spark
tags:
- spark
---
## 问题
业务反馈看板的数据存在缺失，查看看板对应的数据链路，发现中间有一张 dws 表数据缺失了，看该表的任务是正常执行。比对任务脚本 SQL 及执行日志发现，原因是出在一个条件判断，业务逻辑上我们需要过滤出 uid > 10000 的正常数据，但查询的数据底表刚好 uid 字段为 string 类型。在 spark 中优化后的 SQL 却变成了 `CAST(uid AS INT) > 10000`，而 uid 在数值范围上是有可能大于 2^31-1 的，这一部分超出 int 范围的数据因为转换后溢出成负数而使条件判断为 false 被过滤掉。
```sql
select
    *
from
    table_t
where
    date_par = 19700101
    and uid > 10000
```

## 类型转换的逻辑
这里我们可以看一下 spark 中涉及到类型隐式转换的几个处理规则。
1. 在 IN 条件判断中，将每个元素转换成同一更宽类型 `findWiderCommonType`
2. 表间的 UNION、INTERSECT、DISTINCT 集合操作同样为 `findWiderCommonType`
3. 算术表达式中的 string 类型转换（含比较操作）：
   1. 数据类的计算统一转换成 double，比如 `1 + '1234'`,`sum(col@string)`
   2. 时间类型的判断统一转换成 string，比如 `2022-01-01@DATE = col@string`
4. decimal 间的操作，优先取最大的 scale 和最小的 precision（和整数类型的字段比较不存在精度问题）
5. bool 等值比较，转成与非 bool 值字段相同类型（只限于数值类型），true 为 1，false 为 0。
6. case when then 与 else 分支的类型转换 `findWiderCommonType`/`foldLeft(NULL)(findWiderTypeForTwo)`
7. 在 if 条件判断中的类型转换 `findWiderTypeForTwo`
8. 与期望类型的转换，在函数中我们往往会传一些非函数签名类型的参数，在 spark analyzer 中会尝试将所给的参数向目标类型转换。
> findWiderTypeForTwo 规则：
> 1. decimal 与整数类型转化成 decimal
> 2. decimal 与浮点数类型统一转化成 double
> 3. 数字类型按 byte -> short -> integer -> long -> float -> double 优先级提升
> 4. 时间类型统一转化为 timestamp
> 5. 当类型中有 string 而其它非 bool 和 binary 的原子类型时，统一转化为 string

当无法满足上述转换规则则报错。

## 结论
实际上按照上述转换规则 uid 字段应该是转换成 double 才对，拉取代码到本地验证也确实如此，这里猜测不一致应该是线上运行的框架有加载其它的规则或改动。
当然这里只讨论 spark 的转换，每个引擎都有各自的一套逻辑，规则存在差异，特别是现在平台都把所有执行引擎封装在背后，因此不要期望我们直觉所想的在任务中会得到我们期望的结果，避免这类问题的最好方法就是不要让它发生：
1. 对于业务同一个字段始终统一类型，并在底层处理好。
2. 需要对两个不同类型的字段做操作时，显式地使用 cast 转换。