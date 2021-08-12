---
layout: post
title: 装修Blog与Terminal
date: 2021-08-12 22:49:00 +0800
tags:
- tools
---

最近打开了好久没更新的博客，感觉已经有点破败不堪。自从上次在hexo上尝试把org的文件转成渲染好的html文件失败劝退后再没打理过。最近几天顺手和终端一起翻新了下，这里主要记录下我的blog和terminal的配置过程。
### Terminal
mbp上的终端我主要是用iterm2 + oh my zsh + tmux. 

iterm2这里主要用到了batman的配色，但要把red的颜色改成橘色，避免混淆报错的输出。选择color256，字体随意，mono即可。勾选applications in terminal may access clipboard，保证在tmux中能直接Command+C/V操作剪切板。

oh-my-zsh 只使用最常见的几个插件，可以google之，主题使用了agnoster，有个小问题是dir path如果过长时右侧就没什么空间了，不过影响不大，可以使用另一个主题[bullet-train]或自定义segment来解决。顺便提一下，由于没有用ssh连接客户端，一般连接的都是自己的服务器，直接配个免密ssh + alias也挺方便的。

tmux可以参考[我的配置](https://github.com/amwufiv/dotfiles/tree/master/tmux), 如果Ctrl 和 Caps 没有互换的话可能需要修改下prefix，但我强烈建议互换Ctrl 和 Caps（用过都说好）。插件主要使用tmux-continuum来自动保存恢复session，是的电脑重启的话session会丢失 :(，当然也不是完美恢复，比如ssh连接无法找回。tmux-colortag插件主要用来给window tab着色，由于插件没提供显式指定color的配置项，因此如果要指定每个window的颜色的话，可以直接修改插件中的name2color.py脚本，顺便修改下根据id哈希选色。

自从放弃iterm的分屏快捷键，整个人都好起来了XD，最后效果：
![terminal](/image/terminal.png)



### Blog
blog没有使用主题，主要参考了[Feross的博客](https://feross.org/)，这种简洁的风格和配色真的是太赞了！我感觉不用怎么改就是我审美中理想的blog了(还是加了点页脚和代码高亮)。
首先是从hexo迁移到Jekyll，因为hexo设计之初就是为了优化Jekyll的速度，所以两者结构配置我感觉都没什么区别，学习成本大概就是要了解一下ruby。

由于post和postlist主要是参考上述blog，详细参见_sass/style.scss。tag自动生成用ruby写了一个还是比较简单。字体比较推荐NotoSansCJK，但不知为何下载的otf文件配置完不生效，查询了一下css应该是支持的，转成ttf也不行无奈放弃。代码高亮一在config配置hightlighter，二通过`rougify style github > github.css` 生成想要的主题样式然后import即可。

部署时发现github已经支持了自定义域名的https证书，真不错！然而部署完发现自定义的plugins ghpages不支持，github只支持[很少的几个插件](https://pages.github.com/versions/)，解决方案可以自己站点部署(还要安装nginx、Lets Encrypt、ruby env等比较麻烦)，拉个分支本地直接build push，或者用github action 定时自动build。


todo：
1. 继续org-converter，搜了一下解决方案，发现简单得只是引用了ruby的org parser依赖...主要还要加高亮，感觉自己实现一个也不是特别难，后面再写一下。
