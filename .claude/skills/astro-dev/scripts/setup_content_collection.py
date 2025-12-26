#!/usr/bin/env python3
"""
Setup Content Collections for Astro
Creates a new content collection with TypeScript schema
"""

import os
import sys
from pathlib import Path

def create_content_collection(collection_name: str, schema_type: str = "blog"):
    """Create a content collection with schema"""
    
    # Create collection directory
    collection_dir = Path(f"src/content/{collection_name}")
    collection_dir.mkdir(parents=True, exist_ok=True)
    
    # Define schema templates
    schemas = {
        "blog": '''import { z, defineCollection } from 'astro:content';

const blogCollection = defineCollection({
  type: 'content',
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

export const collections = {
  '%(name)s': blogCollection,
};''',
        "docs": '''import { z, defineCollection } from 'astro:content';

const docsCollection = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    order: z.number().default(0),
    category: z.string(),
    lastUpdated: z.date().optional(),
    draft: z.boolean().default(false),
  }),
});

export const collections = {
  '%(name)s': docsCollection,
};''',
        "products": '''import { z, defineCollection } from 'astro:content';

const productsCollection = defineCollection({
  type: 'data',
  schema: z.object({
    name: z.string(),
    description: z.string(),
    price: z.number(),
    currency: z.string().default('USD'),
    images: z.array(z.string()),
    category: z.string(),
    inStock: z.boolean().default(true),
    sku: z.string(),
  }),
});

export const collections = {
  '%(name)s': productsCollection,
};''',
    }
    
    # Get schema template
    schema_template = schemas.get(schema_type, schemas["blog"])
    schema_content = schema_template % {"name": collection_name}
    
    # Create config file
    config_file = Path("src/content/config.ts")
    if config_file.exists():
        print(f"⚠️  {config_file} already exists. Please merge manually:")
        print(schema_content)
    else:
        config_file.parent.mkdir(parents=True, exist_ok=True)
        config_file.write_text(schema_content)
        print(f"✅ Created {config_file}")
    
    # Create example content
    if schema_type == "blog":
        example_file = collection_dir / "example-post.md"
        example_content = '''---
title: "Example Blog Post"
description: "This is an example blog post"
pubDate: 2024-01-01
author: "Your Name"
tags: ["astro", "blog"]
draft: false
---

# Example Blog Post

This is an example blog post. Edit or delete this file to create your own content!

## Features

- Markdown support
- Frontmatter metadata
- Type-safe with Zod schema
'''
        example_file.write_text(example_content)
        print(f"✅ Created example: {example_file}")
    
    elif schema_type == "products":
        example_file = collection_dir / "example-product.json"
        example_content = '''{
  "name": "Example Product",
  "description": "This is an example product",
  "price": 29.99,
  "currency": "USD",
  "images": ["/images/product.jpg"],
  "category": "electronics",
  "inStock": true,
  "sku": "PROD-001"
}'''
        example_file.write_text(example_content)
        print(f"✅ Created example: {example_file}")
    
    print(f"\n✅ Content collection '{collection_name}' created successfully!")
    print(f"\nNext steps:")
    print(f"1. Edit src/content/{collection_name}/ to add your content")
    print(f"2. Query in your pages:")
    print(f"   import {{ getCollection }} from 'astro:content';")
    print(f"   const entries = await getCollection('{collection_name}');")

def main():
    if len(sys.argv) < 2:
        print("Usage: python setup_content_collection.py <collection-name> [type]")
        print("\nTypes: blog (default), docs, products")
        print("\nExamples:")
        print("  python setup_content_collection.py blog")
        print("  python setup_content_collection.py docs docs")
        print("  python setup_content_collection.py products products")
        sys.exit(1)
    
    collection_name = sys.argv[1]
    schema_type = sys.argv[2] if len(sys.argv) > 2 else "blog"
    
    if not os.path.exists("package.json"):
        print("❌ Error: Not in an Astro project directory")
        print("   Run this script from your Astro project root")
        sys.exit(1)
    
    create_content_collection(collection_name, schema_type)

if __name__ == "__main__":
    main()
