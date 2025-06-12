+++
title = "Getting a site up and running"
date = 2025-06-09
[taxonomies]
tags = ["zola", "website", "blog"]
+++

After looking around for a good tool to build a personal website, I first came across [elm](https://elm-lang.org/), but due to lack of a 1.0 and seemingly little-to-no progress on the repo I went looking some more and came across [zola](https://www.getzola.org/). Getting started with a project was pretty straightforward... but there were definitely some challenges!

Firstly, every [theme](https://www.getzola.org/themes/) has its own variables to set and organization for getting something up and running. For example, one theme might want a folder structure like
```sh
├───content
│   ├───blog
│   └───pages
```
while others might everything under content or use different names. This requires some trial and error, as despite each theme having some instructions, it seems mostly to be a 'figure it out yourself'.

Secondly it was strange to have this hybrid handlebars / markdown style for things, but I am not a web-developer by any means, so maybe this is normal. But basically, one can define templated HTML with `{% block content %}` but then later put in the `content` folder something like below:
```md
+++
title = "Magnum Opus"
+++
```

However, despite this feeling weird to me at least, getting something up and running is not too bad and feels far easier compared to getting something up and running a decade ago...

I will continue to catalog how this site progresses in future blogs, along with other content, so hope you enjoy!