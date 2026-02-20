---
title: About
date: 2026-02-20
author: Iris Lennon
---

**AIGC**

该项目的 :code:`SSG` 代码中存在着 *AIGC* 内容，你可以使用 :code:`hakyll-init -f ./` 得到的空项目中的 :code:`site.hs` 与该项目仓库根目录下的 :code:`site.hs` 比对。

**Depends On**

如果你想使用由Racket的Pollen支持的 :code:`*.html.pm to *.html` 支持，请安装Racket与Pollen，:code:`raco pkg install pollen` 。本项目不提供二进制文件分发，因此同样需要自行安装合适版本的 :code:`GHC/cabal` 。

*对于自行构建博客内容* 

:code:`cabal build && cabal exec site build` 

**Authorization**

由于使用 *AIGC* 生成部分内容，该项目无法保证完全遵守 `GPLv3 <https://www.gnu.org/licenses/gpl-3.0.en.html>`_ （对于业务逻辑代码部分），但 :code:`./post` 下的内容却可以保证由我原创（ `Iris Lennon <mailto:ningxilai@outlook.com>`_ ），该部分使用 `CC BY-NC-SA 4.0 <https://creativecommons.org/licenses/by-nc-sa/4.0/>`_ 授权。

