# SSL_ERROR_SYSCALL

Posted on December 29, 2024

在提交分支时报出了`OpenSSL SSL_read: SSL_ERROR_SYSCALL, errno 0`的错误。

根据 *正宗咸豆花 at CSDN*
的方案，可以使用SSH绕过HTTPS的OpenSSL延迟，在实际使用中，`git remote set-url origin git@github.com:username/repo.git`，就像这样。

另外的，附上当时的最小实例：

```bash
git clone --depth=1  git@github.com:username/repo.git
cd repo
// git remote add origin git@github.com:username/repo.git
// git push origin master
git add .
git commit -m "last commit"
git push origin master ## git push -u origin master
```
对于凭证登陆，选择 `cache` 则有 `git config --global credential.credentialStore cache`。（`dotnet tool install -g git-credential-manager`）

同步：`cp -rp book/* repo` or `rsync -a ./book/ repo` 。

# Pandoc

Pandoc转化`.md`时有`html`序列化后残留的问题，可以使用`pandoc -f html URL -t commonmark-raw_html -o name.md`的方法解决。

# Reader

下载一DjVu文档后，使用emacs的nov插件无法查看其内容，查看配置注释发现nov是一个 `.epub` 查看器，遂安装djvu，但仍无法查看内容，查询ArchWiki后断定是缺少依赖。安装依赖后仍不显示内容但各命令工作正常，推测是由于djvu插件缺省不显示图片所致，`(setq djvu-image-mode t)` 后正常显示。

``` elisp
(use-package djvu)
```

``` bash
sudo pacman -S djvulibre
```

## to PDF

``` bash
sudo pacman -S libtiff
```

``` bash
ddjvu -format=tiff name(1).djvu name(2).tiff
tiff2pdf -j -o name(3).pdf name(2).tiff
```
