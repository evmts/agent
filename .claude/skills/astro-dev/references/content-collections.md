# Content Collections in Astro

## Overview

Content Collections provide type-safe content management for Markdown/MDX and JSON/YAML data in Astro.

## Setup

### 1. Create Collection Directory

```
src/
└── content/
    ├── config.ts          # Schema definitions
    ├── blog/              # Blog collection
    │   ├── post-1.md
    │   └── post-2.md
    └── products/          # Products collection
        ├── product-1.json
        └── product-2.json
```

### 2. Define Schema

**src/content/config.ts:**
```typescript
import { z, defineCollection } from 'astro:content';

const blogCollection = defineCollection({
  type: 'content', // Markdown/MDX
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.date(),
    author: z.string().default('Anonymous'),
    image: z.object({
      url: z.string(),
      alt: z.string(),
    }).optional(),
    tags: z.array(z.string()).default([]),
    draft: z.boolean().default(false),
  }),
});

const productsCollection = defineCollection({
  type: 'data', // JSON/YAML
  schema: z.object({
    name: z.string(),
    price: z.number(),
    inStock: z.boolean(),
  }),
});

export const collections = {
  'blog': blogCollection,
  'products': productsCollection,
};
```

### 3. Create Content

**src/content/blog/first-post.md:**
```markdown
---
title: "My First Post"
description: "This is my first blog post"
pubDate: 2024-01-01
author: "Your Name"
tags: ["astro", "blog"]
draft: false
---

# My First Post

This is the content of my first post!
```

## Querying Collections

### Get All Entries

```astro
---
import { getCollection } from 'astro:content';

const blogPosts = await getCollection('blog');
---

<ul>
  {blogPosts.map(post => (
    <li>
      <a href={`/blog/${post.slug}`}>
        {post.data.title}
      </a>
    </li>
  ))}
</ul>
```

### Filter Entries

```astro
---
const publishedPosts = await getCollection('blog', ({ data }) => {
  return data.draft !== true;
});

const taggedPosts = await getCollection('blog', ({ data }) => {
  return data.tags.includes('astro');
});
---
```

### Get Single Entry

```astro
---
import { getEntry } from 'astro:content';

const post = await getEntry('blog', 'first-post');
---

<h1>{post.data.title}</h1>
```

## Rendering Content

### Render Markdown

```astro
---
import { getEntry } from 'astro:content';

const post = await getEntry('blog', Astro.params.slug);
const { Content } = await post.render();
---

<article>
  <h1>{post.data.title}</h1>
  <p class="text-gray-600">{post.data.pubDate.toLocaleDateString()}</p>
  <Content />
</article>
```

### Custom Components

```astro
---
const { Content, headings } = await post.render();
---

<article>
  <nav>
    <h2>Table of Contents</h2>
    <ul>
      {headings.map(heading => (
        <li>
          <a href={`#${heading.slug}`}>
            {heading.text}
          </a>
        </li>
      ))}
    </ul>
  </nav>
  
  <Content components={{
    h1: (props) => <h1 class="text-4xl font-bold" {...props} />,
    p: (props) => <p class="my-4" {...props} />,
  }} />
</article>
```

## Dynamic Routes

### Generate Static Paths

```astro
---
// src/pages/blog/[...slug].astro
import { getCollection } from 'astro:content';
import type { GetStaticPaths } from 'astro';

export const getStaticPaths: GetStaticPaths = async () => {
  const posts = await getCollection('blog');
  
  return posts.map(post => ({
    params: { slug: post.slug },
    props: { post },
  }));
};

const { post } = Astro.props;
const { Content } = await post.render();
---

<article>
  <h1>{post.data.title}</h1>
  <Content />
</article>
```

### Pagination

```astro
---
// src/pages/blog/[...page].astro
import { getCollection } from 'astro:content';
import type { GetStaticPaths } from 'astro';

export const getStaticPaths: GetStaticPaths = async ({ paginate }) => {
  const posts = await getCollection('blog');
  const sortedPosts = posts.sort((a, b) => 
    b.data.pubDate.getTime() - a.data.pubDate.getTime()
  );
  
  return paginate(sortedPosts, { pageSize: 10 });
};

const { page } = Astro.props;
---

<div>
  {page.data.map(post => (
    <article>
      <h2>{post.data.title}</h2>
      <p>{post.data.description}</p>
    </article>
  ))}
  
  <nav>
    {page.url.prev && <a href={page.url.prev}>Previous</a>}
    {page.url.next && <a href={page.url.next}>Next</a>}
  </nav>
</div>
```

## Advanced Schemas

### References

```typescript
import { z, defineCollection, reference } from 'astro:content';

const authors = defineCollection({
  type: 'data',
  schema: z.object({
    name: z.string(),
    bio: z.string(),
  }),
});

const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    author: reference('authors'), // Reference to authors collection
  }),
});

export const collections = { authors, blog };
```

```astro
---
const post = await getEntry('blog', 'my-post');
const author = await getEntry('authors', post.data.author);
---

<p>Written by {author.data.name}</p>
```

### Unions

```typescript
const media = defineCollection({
  type: 'data',
  schema: z.discriminatedUnion('type', [
    z.object({
      type: z.literal('video'),
      url: z.string(),
      duration: z.number(),
    }),
    z.object({
      type: z.literal('image'),
      url: z.string(),
      alt: z.string(),
    }),
  ]),
});
```

### Transformations

```typescript
const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    pubDate: z.string().transform(str => new Date(str)),
    tags: z.string().transform(str => str.split(',')),
  }),
});
```

## TypeScript Integration

### Generated Types

Astro automatically generates types for collections:

```typescript
import type { CollectionEntry } from 'astro:content';

type BlogPost = CollectionEntry<'blog'>;
type BlogData = BlogPost['data'];

function processPost(post: BlogPost) {
  console.log(post.data.title);
  console.log(post.slug);
}
```

### Type-Safe Queries

```astro
---
import { getCollection } from 'astro:content';

// TypeScript knows the schema
const posts = await getCollection('blog');
posts[0].data.title; // ✅ string
posts[0].data.nonExistent; // ❌ TypeScript error
---
```

## RSS Feed

```typescript
// src/pages/rss.xml.ts
import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';

export async function GET(context) {
  const posts = await getCollection('blog');
  
  return rss({
    title: 'My Blog',
    description: 'A blog about Astro',
    site: context.site,
    items: posts.map(post => ({
      title: post.data.title,
      pubDate: post.data.pubDate,
      description: post.data.description,
      link: `/blog/${post.slug}/`,
    })),
  });
}
```

## Sitemap

```typescript
// src/pages/sitemap.xml.ts
import { getCollection } from 'astro:content';

export async function GET() {
  const posts = await getCollection('blog');
  
  const urls = posts.map(post => ({
    url: `/blog/${post.slug}`,
    lastmod: post.data.pubDate,
  }));
  
  return new Response(generateSitemap(urls), {
    headers: { 'Content-Type': 'application/xml' },
  });
}
```

## Best Practices

1. **Use schemas** - Type safety prevents errors
2. **Filter drafts** - Don't show draft: true in production
3. **Sort by date** - Use pubDate for chronological order
4. **Cache queries** - getCollection results are cached per request
5. **Use references** - Link related content
6. **Validate images** - Use z.string().url() for image URLs

## Common Patterns

### Tags System

```astro
---
// Get all unique tags
const posts = await getCollection('blog');
const allTags = [...new Set(posts.flatMap(post => post.data.tags))];
---

<nav>
  {allTags.map(tag => (
    <a href={`/tags/${tag}`}>{tag}</a>
  ))}
</nav>
```

### Related Posts

```astro
---
const currentPost = await getEntry('blog', Astro.params.slug);
const allPosts = await getCollection('blog');

const relatedPosts = allPosts
  .filter(post => 
    post.slug !== currentPost.slug &&
    post.data.tags.some(tag => currentPost.data.tags.includes(tag))
  )
  .slice(0, 3);
---

<aside>
  <h2>Related Posts</h2>
  {relatedPosts.map(post => (
    <a href={`/blog/${post.slug}`}>{post.data.title}</a>
  ))}
</aside>
```

## Resources

- [Astro Content Collections Docs](https://docs.astro.build/en/guides/content-collections/)
- [Zod Documentation](https://zod.dev/)
