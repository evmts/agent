#!/usr/bin/env python3
"""
Add View Transitions to Astro layouts
Automatically adds View Transitions API to existing layouts
"""

import os
import sys
import re
from pathlib import Path

def add_view_transitions(layout_file: Path):
    """Add View Transitions to a layout file"""
    
    if not layout_file.exists():
        print(f"❌ Error: Layout file not found: {layout_file}")
        return False
    
    content = layout_file.read_text()
    
    # Check if already has View Transitions
    if 'ViewTransitions' in content:
        print(f"⚠️  {layout_file.name} already has View Transitions")
        return False
    
    # Add import at the top of frontmatter
    if content.startswith('---'):
        # Find the end of frontmatter
        match = re.search(r'^---\n(.*?)\n---', content, re.DOTALL)
        if match:
            frontmatter = match.group(1)
            # Add import
            new_frontmatter = f"import {{ ViewTransitions }} from 'astro:transitions';\n{frontmatter}"
            content = content.replace(match.group(0), f"---\n{new_frontmatter}\n---", 1)
    else:
        # No frontmatter, add it
        content = f"---\nimport {{ ViewTransitions }} from 'astro:transitions';\n---\n\n{content}"
    
    # Add ViewTransitions component to <head>
    if '<head>' in content:
        content = content.replace('</head>', '    <ViewTransitions />\n  </head>', 1)
    else:
        print(f"⚠️  No <head> tag found in {layout_file.name}")
        return False
    
    # Write back
    layout_file.write_text(content)
    print(f"✅ Added View Transitions to {layout_file.name}")
    return True

def add_transition_directives(layout_file: Path):
    """Add helpful transition directives as comments"""
    
    content = layout_file.read_text()
    
    # Add comments about transition directives if not present
    if 'transition:' not in content:
        hints = '''
<!-- View Transitions Directives:
  - transition:animate="slide"     // Slide animation
  - transition:animate="fade"      // Fade animation
  - transition:persist             // Persist element across pages
  - transition:name="unique-name"  // Custom transition name
-->
'''
        # Add before closing </head>
        if '</head>' in content:
            content = content.replace('</head>', f'{hints}  </head>', 1)
            layout_file.write_text(content)
            print(f"✅ Added transition directive hints to {layout_file.name}")

def main():
    if not os.path.exists("package.json"):
        print("❌ Error: Not in an Astro project directory")
        sys.exit(1)
    
    # Find all layout files
    layouts_dir = Path("src/layouts")
    
    if not layouts_dir.exists():
        print("❌ Error: No src/layouts directory found")
        print("   Create a layout first, then run this script")
        sys.exit(1)
    
    layout_files = list(layouts_dir.glob("*.astro"))
    
    if not layout_files:
        print("❌ Error: No .astro layout files found in src/layouts/")
        sys.exit(1)
    
    print(f"Found {len(layout_files)} layout file(s):")
    for lf in layout_files:
        print(f"  - {lf.name}")
    
    print("\nAdding View Transitions...")
    
    success_count = 0
    for layout_file in layout_files:
        if add_view_transitions(layout_file):
            add_transition_directives(layout_file)
            success_count += 1
    
    if success_count > 0:
        print(f"\n✅ Successfully updated {success_count} layout(s)!")
        print("\nNext steps:")
        print("1. Test your site - page transitions should now be animated")
        print("2. Add transition directives to elements:")
        print('   <div transition:animate="slide">...</div>')
        print('   <header transition:persist>...</header>')
        print("\n3. Customize animations in your CSS:")
        print('   ::view-transition-old(root) { animation: fade-out 0.3s; }')
        print('   ::view-transition-new(root) { animation: fade-in 0.3s; }')
        print("\n📚 See references/view-transitions.md for more details")
    else:
        print("\nNo changes made.")

if __name__ == "__main__":
    main()
