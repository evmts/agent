#!/bin/bash

# Fix React imports
find components -name "*.tsx" -exec sed -i '' '1i\
import React from "react";\
' {} \;

# Fix WorkflowContext to SmithersCtx
find components -name "*.tsx" -exec sed -i '' 's/WorkflowContext/SmithersCtx<any>/g' {} \;

# Remove unused ts-expect-error
find components -name "*.tsx" -exec sed -i '' '/\/\/ @ts-expect-error - MDX import/d' {} \;
find agents -name "*.ts" -exec sed -i '' '/\/\/ @ts-expect-error - MDX import/d' {} \;

echo "Fixed type errors"
