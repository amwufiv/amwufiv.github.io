---
layout: post
title:  "Scala中的CanBuildFrom"
date:   2018-07-03 15:18:03 +0800
categories: jekyll update
---
了解CanBuildFrom主要还是因为我对Traversable能够正确处理Option上下文感到很不解（如下），List的flatMap函数能够正确拆掉Option上下文变成`(2,3,4)`，要知道Option也只是简单继承了两个与之无关的特质Product[^Product]和Serializable，为何flatMap能够正确识别Option呢？
```scala
List(1,2,3).flatMap(x=>Some(x+1))
//res2: List[Int] = List(2, 3, 4)
```
看一下List的flatMap函数签名：
`final override def flatMap[B, That](f: A => GenTraversableOnce[B])(implicit bf: CanBuildFrom[List[A], B, That]): That`
flatMap函数要求f是一个返回继承`GenTraversableOnce`特质的函数，那为什么能够返回Option呢，查看编译时的类型变换，发现原来存在一个隐式转换将Option转换成了Iterable：`implicit def option2Iterable[A](xo: Option[A]): Iterable[A]`。该隐式转换函数调用了`toList`方法将Option转换成了List,所以也就符合了f的函数签名，因为`Some(x+1)`被隐式转换成了`List(x+1)`。接下来就比较容易理解了，flatMap函数将具有traversable能力的上下文‘扁平化’，实现上是调用了seq统一将变成seq。

所以说隐式转换虽然能够帮助我们开发更灵活的代码，但也加大了我们去理解别人代码的困难，这点在理解后面String的map函数中更有体会。

## CanBuildFrom
那么CanBuildFrom又是什么呢，仔细看List的map和flatMap函数签名，发现它们都声明了一个隐式的CanBuildFrom参数`bf`。这个参数是用来干什么的呢，查看CanBuildFrom源码，发现bf主要是用来构建Builder的（通过构造函数）。
```scala
trait CanBuildFrom[-From, -Elem, +To] {

  /** Creates a new builder on request of a collection.
   *  @param from  the collection requesting the builder to be created.
   *  @return a builder for collections of type `To` with element type `Elem`.
   *          The collections framework usually arranges things so
   *          that the created builder will build the same kind of collection
   *          as `from`.
   */
  def apply(from: From): Builder[Elem, To]

  /** Creates a new builder from scratch.
   *
   *  @return a builder for collections of type `To` with element type `Elem`.
   *  @see scala.collection.breakOut
   */
  def apply(): Builder[Elem, To]
}
```
例如通过map函数，理论上我们能够将`List[Int]`构建成`Seq[String]`,即根据需要返回合适的集合类型。通过`bf()`构建的`builder`，构造封装B的集合。有趣的是`List`中的`map`函数居然没有使用`bf`的`builder`，而还是自己实现构造了新的`List`，所以通过`List.map`还是转换成了`List`。
而对于`String`的map函数(其实不是String而是`StringOps`的map函数),当f函数将字符串中每个字符转换成`Int`时，map函数会返回`IndexedSeq`类型集合，而如果f函数只是将字符作大写化处理时，map函数仍然会返回`String`。
```scala
"abc".map(_.toInt) 
//res4: scala.collection.immutable.IndexedSeq[Int] = Vector(97, 98, 99)
"abc".map(_.toUpper) 
//res5: String = ABC
```
这是如何实现的呢？原来在Predef中定义了两个隐式方法/参数`fallbackStringCanBuildFrom`和`StringCanBuildFrom`,将f函数返回`Char`时会使用`StringCanBuildFrom`作为`map`的隐式参数，而f函数返回非`Char`时则会调用`fallbackStringCanBuildFrom`隐式方法。




对于`map`，`flatMap`等函数，我们都可以通过传递cbf来构建合适的上下文，尽管函数签名比较让人难以理解。而在[官方的说明中](https://scala-lang.org/blog/2017/05/30/tribulations-canbuildfrom.html)，已经考虑将`CanBuildFrom`这种晦涩难懂且不雅观的构建方式摒弃掉，通过使用map重载的方式实现目前的map函数。

### 构建一个自己bf
那我们有没有办法将“hunter”.map(_.toUpper)也返回indexedSeq呢？当然可以，最简单的我们可以直接显式调用`fallbackStringCanBuildFrom`：
```scala
val s1 = "hunter".map(_.toUpper)(fallbackStringCanBuildFrom)
```
如果了解map的构造方式后我们也可以构造自己的`CanBuildFrom`：
```scala
object Temp {
  def main(args: Array[String]): Unit = {



    val myBF: CanBuildFrom[String, Char, List[Char]] = new CanBuildFrom[String, Char, List[Char]] {
      def apply(from: String) = apply()
      def apply()             = new MyBuilder
    }
    val s = "hunter"
    val l = s.map(_.toUpper)(myBF)
    println(l)
    // l is List(H, U, N, T, E, R)


  }



}

class MyBuilder(list: ListBuffer[Char]) extends ReusableBuilder[Char, List[Char]]{
  def this()={
    this(new ListBuffer[Char])
  }

  override def clear(): Unit = {
    list.clear()
  }

  override def +=(elem: Char): MyBuilder.this.type = {list.append(elem);this}
  override def result(): List[Char] = list.toList
}

```


[^Product]: 题外还有一个有趣的地方，上文讲到Option引入了特质Product，Product主要是实现`productIterator`从而实现向Iterator的转换。在我们声明的case class中，编译器会在编译过程中自动引入Product，所以每当我们声明case class时，总能调用productIterator方法来遍历各元素。
