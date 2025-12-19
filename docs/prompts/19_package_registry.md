# Package Registry Implementation

## Overview

Implement a package registry system for Plue, supporting NPM (JavaScript) and Container/Docker (OCI) registries. This transforms Plue into a complete code hosting platform with integrated package management.

**Scope:**
- NPM registry (npm publish, npm install)
- Container/Docker registry (docker push, docker pull)
- Package versioning with semver support
- Package file storage with blob deduplication
- Authentication for publish/download
- Package metadata and search
- Web UI for browsing packages
- Download statistics

**Out of scope (future features):**
- PyPI, Maven, RubyGems, Cargo, etc. (basic structure supports future addition)
- Package signing/verification
- Package vulnerability scanning
- Package mirrors/proxies
- CDN integration
- Storage quotas (can be added later)

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Backend**: Hono server with middleware
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL with `postgres` client
- **Validation**: Zod v4
- **File Storage**: Bun.file() for blob storage
- **Hash Algorithms**: MD5, SHA1, SHA256, SHA512

## Architecture Overview

### Data Model Hierarchy

```
Package (e.g., "express", "nginx")
  └─> PackageVersion (e.g., "4.18.2", "1.21.0")
       └─> PackageFile (e.g., "express-4.18.2.tgz", "manifest.json")
            └─> PackageBlob (actual file content, deduplicated by hash)
```

### Key Concepts from Gitea

1. **Blob Deduplication**: Multiple files with identical content share one blob
2. **Type-Based Routing**: Each package type has its own API endpoints
3. **Metadata Separation**: Package metadata stored as JSON in database
4. **Composite Keys**: Support for complex file identifiers (e.g., container layers)
5. **Properties System**: Key-value properties for packages, versions, and files

## Database Schema

### File: `/Users/williamcory/plue/db/schema.sql`

Add the following tables after the existing agent state tables:

```sql
-- =============================================================================
-- Package Registry Tables
-- =============================================================================

-- Package types enum (for reference, stored as VARCHAR)
-- Supported types: 'npm', 'container', 'generic'
-- Future types: 'pypi', 'maven', 'cargo', 'rubygems', etc.

-- Packages (top-level package entity)
CREATE TABLE IF NOT EXISTS packages (
  id SERIAL PRIMARY KEY,
  owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  repo_id INTEGER REFERENCES repositories(id) ON DELETE SET NULL,
  type VARCHAR(50) NOT NULL CHECK (type IN ('npm', 'container', 'generic')),
  name VARCHAR(512) NOT NULL,
  lower_name VARCHAR(512) NOT NULL,
  semver_compatible BOOLEAN NOT NULL DEFAULT false,
  is_internal BOOLEAN NOT NULL DEFAULT false, -- for internal/system packages
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(owner_id, type, lower_name)
);

CREATE INDEX IF NOT EXISTS idx_packages_owner_type ON packages(owner_id, type);
CREATE INDEX IF NOT EXISTS idx_packages_lower_name ON packages(lower_name);
CREATE INDEX IF NOT EXISTS idx_packages_repo ON packages(repo_id);

-- Package versions
CREATE TABLE IF NOT EXISTS package_versions (
  id SERIAL PRIMARY KEY,
  package_id INTEGER NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
  creator_id INTEGER NOT NULL REFERENCES users(id) ON DELETE SET NULL,
  version VARCHAR(255) NOT NULL,
  lower_version VARCHAR(255) NOT NULL,
  metadata_json TEXT, -- JSON metadata (package-type specific)
  is_internal BOOLEAN NOT NULL DEFAULT false,
  download_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(package_id, lower_version)
);

CREATE INDEX IF NOT EXISTS idx_package_versions_package ON package_versions(package_id);
CREATE INDEX IF NOT EXISTS idx_package_versions_created ON package_versions(created_at DESC);

-- Package files (references to blobs)
CREATE TABLE IF NOT EXISTS package_files (
  id SERIAL PRIMARY KEY,
  version_id INTEGER NOT NULL REFERENCES package_versions(id) ON DELETE CASCADE,
  blob_id INTEGER NOT NULL REFERENCES package_blobs(id) ON DELETE RESTRICT,
  name VARCHAR(512) NOT NULL,
  lower_name VARCHAR(512) NOT NULL,
  composite_key VARCHAR(512) DEFAULT '', -- for complex file identifiers (container layers, etc.)
  is_lead BOOLEAN NOT NULL DEFAULT false, -- primary file (e.g., main tarball)
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(version_id, lower_name, composite_key)
);

CREATE INDEX IF NOT EXISTS idx_package_files_version ON package_files(version_id);
CREATE INDEX IF NOT EXISTS idx_package_files_blob ON package_files(blob_id);
CREATE INDEX IF NOT EXISTS idx_package_files_lower_name ON package_files(lower_name);

-- Package blobs (deduplicated file storage)
CREATE TABLE IF NOT EXISTS package_blobs (
  id SERIAL PRIMARY KEY,
  size BIGINT NOT NULL,
  hash_md5 CHAR(32) NOT NULL,
  hash_sha1 CHAR(40) NOT NULL,
  hash_sha256 CHAR(64) NOT NULL,
  hash_sha512 CHAR(128) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(hash_sha256)
);

CREATE INDEX IF NOT EXISTS idx_package_blobs_md5 ON package_blobs(hash_md5);
CREATE INDEX IF NOT EXISTS idx_package_blobs_sha1 ON package_blobs(hash_sha1);
CREATE INDEX IF NOT EXISTS idx_package_blobs_sha256 ON package_blobs(hash_sha256);
CREATE INDEX IF NOT EXISTS idx_package_blobs_sha512 ON package_blobs(hash_sha512);

-- Package properties (flexible key-value storage)
CREATE TABLE IF NOT EXISTS package_properties (
  id SERIAL PRIMARY KEY,
  ref_type VARCHAR(20) NOT NULL CHECK (ref_type IN ('package', 'version', 'file')),
  ref_id INTEGER NOT NULL, -- references packages.id, package_versions.id, or package_files.id
  name VARCHAR(255) NOT NULL,
  value TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_package_properties_ref ON package_properties(ref_type, ref_id);
CREATE INDEX IF NOT EXISTS idx_package_properties_name ON package_properties(name);

-- Package blob uploads (for chunked/resumable uploads)
CREATE TABLE IF NOT EXISTS package_blob_uploads (
  id VARCHAR(64) PRIMARY KEY, -- UUID
  owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL,
  name VARCHAR(512) NOT NULL,
  bytes_received BIGINT NOT NULL DEFAULT 0,
  hash_state_bytes BYTEA, -- serialized hash state for resumable uploads
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_package_blob_uploads_owner ON package_blob_uploads(owner_id);
CREATE INDEX IF NOT EXISTS idx_package_blob_uploads_updated ON package_blob_uploads(updated_at);
```

## File Storage Structure

### Storage Location

```
/Users/williamcory/plue/storage/packages/
  ├── blobs/
  │   └── {first_2_chars}/
  │       └── {next_2_chars}/
  │           └── {sha256}.blob
  └── uploads/
      └── {upload_id}.tmp
```

### Blob Storage Implementation

**File**: `/Users/williamcory/plue/core/package-storage.ts`

```typescript
import { join } from 'path';

/**
 * Package blob storage manager
 * Handles storage and retrieval of package blobs with hash-based deduplication
 */
export class PackageBlobStorage {
  private baseDir: string;

  constructor(baseDir: string = './storage/packages') {
    this.baseDir = baseDir;
  }

  /**
   * Get blob path from SHA256 hash
   * Example: abc123... -> blobs/ab/c1/abc123...blob
   */
  getBlobPath(sha256: string): string {
    const first2 = sha256.substring(0, 2);
    const next2 = sha256.substring(2, 4);
    return join(this.baseDir, 'blobs', first2, next2, `${sha256}.blob`);
  }

  /**
   * Get upload path from upload ID
   */
  getUploadPath(uploadId: string): string {
    return join(this.baseDir, 'uploads', `${uploadId}.tmp`);
  }

  /**
   * Save blob to storage
   */
  async saveBlob(sha256: string, data: Buffer): Promise<void> {
    const path = this.getBlobPath(sha256);
    const dir = join(path, '..');
    await Bun.write(path, data);
  }

  /**
   * Read blob from storage
   */
  async readBlob(sha256: string): Promise<ReadableStream> {
    const path = this.getBlobPath(sha256);
    const file = Bun.file(path);
    if (!(await file.exists())) {
      throw new Error(`Blob not found: ${sha256}`);
    }
    return file.stream();
  }

  /**
   * Delete blob from storage
   */
  async deleteBlob(sha256: string): Promise<void> {
    const path = this.getBlobPath(sha256);
    await Bun.write(path, new Uint8Array(0)).then(() =>
      // Bun doesn't have unlink, use system rm
      Bun.spawn(['rm', path])
    );
  }

  /**
   * Check if blob exists
   */
  async blobExists(sha256: string): Promise<boolean> {
    const file = Bun.file(this.getBlobPath(sha256));
    return await file.exists();
  }
}
```

## Database Layer

### File: `/Users/williamcory/plue/db/packages.ts`

```typescript
import { db } from './index';
import type { Package, PackageVersion, PackageFile, PackageBlob } from './types';

/**
 * Package database operations
 */

export async function createOrGetPackage(params: {
  ownerId: number;
  type: string;
  name: string;
  semverCompatible: boolean;
}): Promise<Package> {
  const lowerName = params.name.toLowerCase();

  // Try to insert, return existing if duplicate
  const result = await db.query(
    `INSERT INTO packages (owner_id, type, name, lower_name, semver_compatible)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (owner_id, type, lower_name) DO UPDATE SET owner_id = EXCLUDED.owner_id
     RETURNING *`,
    [params.ownerId, params.type, params.name, lowerName, params.semverCompatible]
  );

  return result.rows[0];
}

export async function createOrGetPackageVersion(params: {
  packageId: number;
  creatorId: number;
  version: string;
  metadataJson: string;
}): Promise<{ version: PackageVersion; created: boolean }> {
  const lowerVersion = params.version.toLowerCase();

  // Check if exists
  const existing = await db.query(
    `SELECT * FROM package_versions WHERE package_id = $1 AND lower_version = $2`,
    [params.packageId, lowerVersion]
  );

  if (existing.rows.length > 0) {
    return { version: existing.rows[0], created: false };
  }

  // Create new
  const result = await db.query(
    `INSERT INTO package_versions (package_id, creator_id, version, lower_version, metadata_json)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [params.packageId, params.creatorId, params.version, lowerVersion, params.metadataJson]
  );

  return { version: result.rows[0], created: true };
}

export async function createOrGetBlob(params: {
  size: number;
  hashMd5: string;
  hashSha1: string;
  hashSha256: string;
  hashSha512: string;
}): Promise<{ blob: PackageBlob; created: boolean }> {
  // Check if blob exists
  const existing = await db.query(
    `SELECT * FROM package_blobs WHERE hash_sha256 = $1`,
    [params.hashSha256]
  );

  if (existing.rows.length > 0) {
    return { blob: existing.rows[0], created: false };
  }

  // Create new blob
  const result = await db.query(
    `INSERT INTO package_blobs (size, hash_md5, hash_sha1, hash_sha256, hash_sha512)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [params.size, params.hashMd5, params.hashSha1, params.hashSha256, params.hashSha512]
  );

  return { blob: result.rows[0], created: true };
}

export async function createPackageFile(params: {
  versionId: number;
  blobId: number;
  name: string;
  compositeKey?: string;
  isLead: boolean;
}): Promise<PackageFile> {
  const lowerName = params.name.toLowerCase();

  const result = await db.query(
    `INSERT INTO package_files (version_id, blob_id, name, lower_name, composite_key, is_lead)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`,
    [params.versionId, params.blobId, params.name, lowerName, params.compositeKey || '', params.isLead]
  );

  return result.rows[0];
}

export async function getPackageByName(ownerId: number, type: string, name: string): Promise<Package | null> {
  const result = await db.query(
    `SELECT * FROM packages WHERE owner_id = $1 AND type = $2 AND lower_name = $3`,
    [ownerId, type, name.toLowerCase()]
  );
  return result.rows[0] || null;
}

export async function getPackageVersions(packageId: number): Promise<PackageVersion[]> {
  const result = await db.query(
    `SELECT * FROM package_versions WHERE package_id = $1 ORDER BY created_at DESC`,
    [packageId]
  );
  return result.rows;
}

export async function getPackageVersion(packageId: number, version: string): Promise<PackageVersion | null> {
  const result = await db.query(
    `SELECT * FROM package_versions WHERE package_id = $1 AND lower_version = $2`,
    [packageId, version.toLowerCase()]
  );
  return result.rows[0] || null;
}

export async function getPackageFiles(versionId: number): Promise<PackageFile[]> {
  const result = await db.query(
    `SELECT pf.*, pb.*
     FROM package_files pf
     JOIN package_blobs pb ON pf.blob_id = pb.id
     WHERE pf.version_id = $1`,
    [versionId]
  );
  return result.rows;
}

export async function incrementDownloadCount(versionId: number): Promise<void> {
  await db.query(
    `UPDATE package_versions SET download_count = download_count + 1 WHERE id = $1`,
    [versionId]
  );
}

export async function searchPackages(params: {
  ownerId?: number;
  type?: string;
  query?: string;
  limit?: number;
  offset?: number;
}): Promise<Array<Package & { latest_version: string }>> {
  let sql = `
    SELECT p.*,
           (SELECT version FROM package_versions
            WHERE package_id = p.id
            ORDER BY created_at DESC LIMIT 1) as latest_version
    FROM packages p
    WHERE 1=1
  `;
  const queryParams: any[] = [];
  let paramIndex = 1;

  if (params.ownerId) {
    sql += ` AND p.owner_id = $${paramIndex++}`;
    queryParams.push(params.ownerId);
  }

  if (params.type) {
    sql += ` AND p.type = $${paramIndex++}`;
    queryParams.push(params.type);
  }

  if (params.query) {
    sql += ` AND p.lower_name LIKE $${paramIndex++}`;
    queryParams.push(`%${params.query.toLowerCase()}%`);
  }

  sql += ` ORDER BY p.created_at DESC`;

  if (params.limit) {
    sql += ` LIMIT $${paramIndex++}`;
    queryParams.push(params.limit);
  }

  if (params.offset) {
    sql += ` OFFSET $${paramIndex++}`;
    queryParams.push(params.offset);
  }

  const result = await db.query(sql, queryParams);
  return result.rows;
}
```

### File: `/Users/williamcory/plue/db/types.ts`

Add to existing types:

```typescript
export interface Package {
  id: number;
  owner_id: number;
  repo_id: number | null;
  type: string;
  name: string;
  lower_name: string;
  semver_compatible: boolean;
  is_internal: boolean;
  created_at: Date;
}

export interface PackageVersion {
  id: number;
  package_id: number;
  creator_id: number;
  version: string;
  lower_version: string;
  metadata_json: string;
  is_internal: boolean;
  download_count: number;
  created_at: Date;
}

export interface PackageFile {
  id: number;
  version_id: number;
  blob_id: number;
  name: string;
  lower_name: string;
  composite_key: string;
  is_lead: boolean;
  created_at: Date;
}

export interface PackageBlob {
  id: number;
  size: number;
  hash_md5: string;
  hash_sha1: string;
  hash_sha256: string;
  hash_sha512: string;
  created_at: Date;
}

export interface PackageBlobUpload {
  id: string;
  owner_id: number;
  type: string;
  name: string;
  bytes_received: number;
  hash_state_bytes: Buffer | null;
  created_at: Date;
  updated_at: Date;
}
```

## NPM Registry Implementation

### NPM Metadata Types

**File**: `/Users/williamcory/plue/core/packages/npm/types.ts`

```typescript
/**
 * NPM package metadata (stored in package_versions.metadata_json)
 */
export interface NpmMetadata {
  scope?: string;
  name: string;
  description?: string;
  author?: string;
  license?: string;
  project_url?: string;
  keywords?: string[];
  dependencies?: Record<string, string>;
  dev_dependencies?: Record<string, string>;
  peer_dependencies?: Record<string, string>;
  optional_dependencies?: Record<string, string>;
  bin?: Record<string, string>;
  readme?: string;
  repository?: {
    type: string;
    url: string;
  };
}

/**
 * NPM publish request format
 */
export interface NpmPublishRequest {
  _id: string;
  name: string;
  description?: string;
  'dist-tags': Record<string, string>;
  versions: Record<string, NpmVersionManifest>;
  _attachments: Record<string, NpmAttachment>;
}

export interface NpmVersionManifest {
  name: string;
  version: string;
  description?: string;
  author?: string;
  license?: string;
  repository?: { type: string; url: string };
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
  peerDependencies?: Record<string, string>;
  optionalDependencies?: Record<string, string>;
  bin?: Record<string, string>;
  scripts?: Record<string, string>;
  keywords?: string[];
  dist: {
    shasum: string; // SHA1
    integrity?: string; // SHA512 in base64
    tarball: string;
  };
  _npmUser?: {
    name: string;
    email: string;
  };
}

export interface NpmAttachment {
  content_type: string;
  data: string; // base64 encoded tarball
  length: number;
}

/**
 * NPM package metadata response (for `npm view` or registry API)
 */
export interface NpmPackageResponse {
  _id: string;
  name: string;
  description?: string;
  'dist-tags': Record<string, string>;
  versions: Record<string, NpmVersionManifest>;
  time: Record<string, string>; // version -> timestamp
  readme?: string;
  maintainers: Array<{ name: string; email: string }>;
  author?: { name: string; email: string };
  repository?: { type: string; url: string };
  license?: string;
  keywords?: string[];
}
```

### NPM API Routes

**File**: `/Users/williamcory/plue/server/routes/packages/npm.ts`

```typescript
import { Hono } from 'hono';
import { z } from 'zod';
import { createHash } from 'crypto';
import {
  createOrGetPackage,
  createOrGetPackageVersion,
  createOrGetBlob,
  createPackageFile,
  getPackageByName,
  getPackageVersions,
  getPackageVersion,
  getPackageFiles,
  incrementDownloadCount
} from '../../../db/packages';
import { PackageBlobStorage } from '../../../core/package-storage';
import type { NpmPublishRequest, NpmPackageResponse, NpmMetadata } from '../../../core/packages/npm/types';

const app = new Hono();
const storage = new PackageBlobStorage();

/**
 * NPM registry endpoints
 *
 * Spec: https://github.com/npm/registry/blob/master/docs/REGISTRY-API.md
 */

// Helper: Extract package name from params (supports scoped packages)
function getPackageName(scope: string | undefined, id: string): string {
  return scope ? `@${scope}/${id}` : id;
}

// Helper: Calculate multiple hashes
async function calculateHashes(data: Buffer): Promise<{
  md5: string;
  sha1: string;
  sha256: string;
  sha512: string;
}> {
  return {
    md5: createHash('md5').update(data).digest('hex'),
    sha1: createHash('sha1').update(data).digest('hex'),
    sha256: createHash('sha256').update(data).digest('hex'),
    sha512: createHash('sha512').update(data).digest('hex'),
  };
}

/**
 * GET /@:scope/:id - Get package metadata (scoped)
 * GET /:id - Get package metadata (unscoped)
 */
app.get('/:id', async (c) => {
  const scope = c.req.param('scope');
  const id = c.req.param('id');
  const packageName = getPackageName(scope, id);

  // TODO: Get owner from auth
  const ownerId = 1; // placeholder

  const pkg = await getPackageByName(ownerId, 'npm', packageName);
  if (!pkg) {
    return c.json({ error: 'Package not found' }, 404);
  }

  const versions = await getPackageVersions(pkg.id);

  // Build NPM-compatible response
  const response: NpmPackageResponse = {
    _id: packageName,
    name: packageName,
    'dist-tags': { latest: versions[0]?.version || '' },
    versions: {},
    time: {},
    maintainers: [],
  };

  for (const ver of versions) {
    const metadata: NpmMetadata = JSON.parse(ver.metadata_json);
    const files = await getPackageFiles(ver.id);
    const tarball = files.find(f => f.is_lead);

    response.versions[ver.version] = {
      name: packageName,
      version: ver.version,
      description: metadata.description,
      author: metadata.author,
      license: metadata.license,
      repository: metadata.repository,
      dependencies: metadata.dependencies,
      devDependencies: metadata.dev_dependencies,
      peerDependencies: metadata.peer_dependencies,
      optionalDependencies: metadata.optional_dependencies,
      bin: metadata.bin,
      keywords: metadata.keywords,
      dist: {
        shasum: tarball?.hash_sha1 || '',
        tarball: `${c.req.url}/-/${packageName}-${ver.version}.tgz`,
      },
    };

    response.time[ver.version] = ver.created_at.toISOString();
  }

  return c.json(response);
});

/**
 * GET /:id/-/:filename - Download package tarball
 * Example: /express/-/express-4.18.2.tgz
 */
app.get('/:id/-/:filename', async (c) => {
  const scope = c.req.param('scope');
  const id = c.req.param('id');
  const filename = c.req.param('filename');
  const packageName = getPackageName(scope, id);

  // Extract version from filename (e.g., express-4.18.2.tgz -> 4.18.2)
  const match = filename.match(/-([\d.]+(?:-[\w.]+)?)\.(tgz|tar\.gz)$/);
  if (!match) {
    return c.json({ error: 'Invalid filename' }, 400);
  }
  const version = match[1];

  const ownerId = 1; // TODO: Get from auth
  const pkg = await getPackageByName(ownerId, 'npm', packageName);
  if (!pkg) {
    return c.json({ error: 'Package not found' }, 404);
  }

  const pkgVersion = await getPackageVersion(pkg.id, version);
  if (!pkgVersion) {
    return c.json({ error: 'Version not found' }, 404);
  }

  const files = await getPackageFiles(pkgVersion.id);
  const tarball = files.find(f => f.is_lead);
  if (!tarball) {
    return c.json({ error: 'Tarball not found' }, 404);
  }

  // Increment download counter
  await incrementDownloadCount(pkgVersion.id);

  // Stream the blob
  const stream = await storage.readBlob(tarball.hash_sha256);

  return c.body(stream, {
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': `attachment; filename="${filename}"`,
    },
  });
});

/**
 * PUT /:id - Publish package
 * Body: NPM publish request with embedded tarball
 */
app.put('/:id', async (c) => {
  const scope = c.req.param('scope');
  const id = c.req.param('id');
  const packageName = getPackageName(scope, id);

  const body: NpmPublishRequest = await c.req.json();

  // Validate package name matches
  if (body.name !== packageName) {
    return c.json({ error: 'Package name mismatch' }, 400);
  }

  const ownerId = 1; // TODO: Get from auth (ctx.user.id)
  const creatorId = 1;

  // Create or get package
  const pkg = await createOrGetPackage({
    ownerId,
    type: 'npm',
    name: packageName,
    semverCompatible: true,
  });

  // Process each version
  for (const [version, manifest] of Object.entries(body.versions)) {
    // Parse metadata
    const metadata: NpmMetadata = {
      name: manifest.name,
      description: manifest.description,
      author: manifest.author,
      license: manifest.license,
      repository: manifest.repository,
      dependencies: manifest.dependencies,
      dev_dependencies: manifest.devDependencies,
      peer_dependencies: manifest.peerDependencies,
      optional_dependencies: manifest.optionalDependencies,
      bin: manifest.bin,
      keywords: manifest.keywords,
    };

    // Create version
    const { version: pkgVersion, created } = await createOrGetPackageVersion({
      packageId: pkg.id,
      creatorId,
      version,
      metadataJson: JSON.stringify(metadata),
    });

    if (!created) {
      continue; // Version already exists
    }

    // Process attachments (tarball)
    const attachmentKey = Object.keys(body._attachments)[0];
    if (!attachmentKey) {
      return c.json({ error: 'No attachment found' }, 400);
    }

    const attachment = body._attachments[attachmentKey];
    const tarballData = Buffer.from(attachment.data, 'base64');

    // Calculate hashes
    const hashes = await calculateHashes(tarballData);

    // Verify SHA1 from manifest
    if (hashes.sha1 !== manifest.dist.shasum) {
      return c.json({ error: 'SHA1 mismatch' }, 400);
    }

    // Create or get blob
    const { blob, created: blobCreated } = await createOrGetBlob({
      size: tarballData.length,
      hashMd5: hashes.md5,
      hashSha1: hashes.sha1,
      hashSha256: hashes.sha256,
      hashSha512: hashes.sha512,
    });

    // Save blob to storage (if new)
    if (blobCreated) {
      await storage.saveBlob(hashes.sha256, tarballData);
    }

    // Create package file
    await createPackageFile({
      versionId: pkgVersion.id,
      blobId: blob.id,
      name: attachmentKey,
      isLead: true,
    });
  }

  return c.json({ success: true });
});

/**
 * DELETE /:id/-rev/:rev - Unpublish package version
 */
app.delete('/:id/-rev/:rev', async (c) => {
  // TODO: Implement unpublish
  return c.json({ error: 'Not implemented' }, 501);
});

export default app;
```

## Container/Docker Registry Implementation

### Container Metadata Types

**File**: `/Users/williamcory/plue/core/packages/container/types.ts`

```typescript
/**
 * Container/OCI registry types
 * Spec: https://github.com/opencontainers/distribution-spec
 */

export interface ContainerMetadata {
  type: 'oci' | 'helm';
  is_tagged: boolean;
  platform?: string; // e.g., linux/amd64
  description?: string;
  authors?: string[];
  licenses?: string;
  project_url?: string;
  repository_url?: string;
  documentation_url?: string;
  labels?: Record<string, string>;
  image_layers?: string[];
  manifests?: Array<{
    platform: string;
    digest: string;
    size: number;
  }>;
}

export interface OciManifest {
  schemaVersion: number;
  mediaType: string;
  config: {
    mediaType: string;
    size: number;
    digest: string;
  };
  layers: Array<{
    mediaType: string;
    size: number;
    digest: string;
  }>;
  annotations?: Record<string, string>;
}

export interface OciImageConfig {
  architecture: string;
  os: string;
  config: {
    User?: string;
    Env?: string[];
    Cmd?: string[];
    Labels?: Record<string, string>;
  };
  rootfs: {
    type: string;
    diff_ids: string[];
  };
  history?: Array<{
    created?: string;
    created_by?: string;
  }>;
}
```

### Container API Routes (Partial)

**File**: `/Users/williamcory/plue/server/routes/packages/container.ts`

```typescript
import { Hono } from 'hono';
import { createHash } from 'crypto';

const app = new Hono();

/**
 * OCI Distribution Spec endpoints
 * Spec: https://github.com/opencontainers/distribution-spec/blob/main/spec.md
 */

/**
 * GET /v2/ - Check API version
 */
app.get('/v2/', (c) => {
  c.header('Docker-Distribution-Api-Version', 'registry/2.0');
  return c.json({});
});

/**
 * GET /v2/:image/tags/list - List tags
 */
app.get('/v2/:image/tags/list', async (c) => {
  const image = c.req.param('image');

  // TODO: Get owner from auth, query database

  return c.json({
    name: image,
    tags: ['latest', '1.0.0'],
  });
});

/**
 * GET /v2/:image/manifests/:reference - Get manifest
 */
app.get('/v2/:image/manifests/:reference', async (c) => {
  const image = c.req.param('image');
  const reference = c.req.param('reference'); // tag or digest

  // TODO: Query database for manifest
  // Return OCI manifest JSON

  return c.json({
    schemaVersion: 2,
    mediaType: 'application/vnd.oci.image.manifest.v1+json',
    config: {
      mediaType: 'application/vnd.oci.image.config.v1+json',
      size: 1234,
      digest: 'sha256:abcdef...',
    },
    layers: [],
  });
});

/**
 * PUT /v2/:image/manifests/:reference - Upload manifest
 */
app.put('/v2/:image/manifests/:reference', async (c) => {
  const image = c.req.param('image');
  const reference = c.req.param('reference');

  const manifest = await c.req.json();

  // TODO: Validate manifest, store in database

  c.header('Docker-Distribution-Api-Version', 'registry/2.0');
  return c.json({}, 201);
});

/**
 * GET /v2/:image/blobs/:digest - Download blob
 */
app.get('/v2/:image/blobs/:digest', async (c) => {
  const image = c.req.param('image');
  const digest = c.req.param('digest'); // sha256:...

  // TODO: Stream blob from storage

  return c.body(null); // placeholder
});

/**
 * POST /v2/:image/blobs/uploads/ - Initiate blob upload
 */
app.post('/v2/:image/blobs/uploads/', async (c) => {
  const image = c.req.param('image');

  // Generate upload UUID
  const uploadId = crypto.randomUUID();

  // TODO: Create upload session in database

  c.header('Location', `/v2/${image}/blobs/uploads/${uploadId}`);
  c.header('Docker-Upload-Uuid', uploadId);
  return c.json({}, 202);
});

/**
 * PATCH /v2/:image/blobs/uploads/:uuid - Upload blob chunk
 */
app.patch('/v2/:image/blobs/uploads/:uuid', async (c) => {
  const uuid = c.req.param('uuid');

  // TODO: Append chunk to upload

  c.header('Location', `/v2/${c.req.param('image')}/blobs/uploads/${uuid}`);
  c.header('Docker-Upload-Uuid', uuid);
  c.header('Range', '0-1234');
  return c.json({}, 202);
});

/**
 * PUT /v2/:image/blobs/uploads/:uuid - Complete blob upload
 */
app.put('/v2/:image/blobs/uploads/:uuid', async (c) => {
  const uuid = c.req.param('uuid');
  const digest = c.req.query('digest'); // sha256:...

  // TODO: Finalize upload, verify digest, create blob

  c.header('Docker-Content-Digest', digest || '');
  return c.json({}, 201);
});

export default app;
```

## API Routes Setup

### File: `/Users/williamcory/plue/server/routes/packages/index.ts`

```typescript
import { Hono } from 'hono';
import npmRoutes from './npm';
import containerRoutes from './container';

const app = new Hono();

// NPM registry at /api/packages/{user}/npm/
app.route('/npm', npmRoutes);

// Container registry at /v2/ (OCI spec requires root path)
// Mount container routes at server level, not here

export default app;
```

### File: `/Users/williamcory/plue/server/index.ts`

Update to mount package routes:

```typescript
import packageRoutes from './routes/packages';
import containerRoutes from './routes/packages/container';

// ... existing code ...

// NPM packages (per-user)
app.route('/api/packages/:user', packageRoutes);

// Container registry (root /v2/ path)
app.route('/', containerRoutes);
```

## Web UI

### Package List Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/packages/index.astro`

```astro
---
import Layout from '../../../layouts/Layout.astro';
import { db } from '../../../lib/db';

const { user } = Astro.params;

// Get user
const userResult = await db.query('SELECT * FROM users WHERE username = $1', [user]);
if (userResult.rows.length === 0) {
  return Astro.redirect('/404');
}
const owner = userResult.rows[0];

// Get packages
const packagesResult = await db.query(`
  SELECT p.*,
         (SELECT version FROM package_versions
          WHERE package_id = p.id
          ORDER BY created_at DESC LIMIT 1) as latest_version,
         (SELECT SUM(download_count) FROM package_versions
          WHERE package_id = p.id) as total_downloads
  FROM packages p
  WHERE p.owner_id = $1
  ORDER BY p.created_at DESC
`, [owner.id]);
const packages = packagesResult.rows;
---

<Layout title={`${user}'s Packages`}>
  <div class="container">
    <h1>{user}/packages</h1>

    <div class="package-types">
      <a href="?type=npm">NPM</a>
      <a href="?type=container">Container</a>
      <a href="?type=all">All</a>
    </div>

    {packages.length === 0 ? (
      <p>No packages published yet.</p>
    ) : (
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Type</th>
            <th>Latest Version</th>
            <th>Downloads</th>
            <th>Created</th>
          </tr>
        </thead>
        <tbody>
          {packages.map((pkg) => (
            <tr>
              <td><a href={`/${user}/packages/${pkg.type}/${pkg.name}`}>{pkg.name}</a></td>
              <td>{pkg.type}</td>
              <td>{pkg.latest_version}</td>
              <td>{pkg.total_downloads || 0}</td>
              <td>{new Date(pkg.created_at).toLocaleDateString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    )}
  </div>
</Layout>
```

### Package Detail Page

**File**: `/Users/williamcory/plue/ui/pages/[user]/packages/[type]/[...name].astro`

```astro
---
import Layout from '../../../../layouts/Layout.astro';
import { db } from '../../../../lib/db';

const { user, type, name } = Astro.params;
const packageName = Astro.params.name; // May include slashes for scoped packages

// Get user
const userResult = await db.query('SELECT * FROM users WHERE username = $1', [user]);
if (userResult.rows.length === 0) {
  return Astro.redirect('/404');
}
const owner = userResult.rows[0];

// Get package
const pkgResult = await db.query(
  'SELECT * FROM packages WHERE owner_id = $1 AND type = $2 AND lower_name = $3',
  [owner.id, type, packageName.toLowerCase()]
);
if (pkgResult.rows.length === 0) {
  return Astro.redirect('/404');
}
const pkg = pkgResult.rows[0];

// Get versions
const versionsResult = await db.query(
  'SELECT * FROM package_versions WHERE package_id = $1 ORDER BY created_at DESC',
  [pkg.id]
);
const versions = versionsResult.rows;

// Parse latest version metadata
const latestMetadata = versions[0] ? JSON.parse(versions[0].metadata_json) : null;
---

<Layout title={`${pkg.name} - Packages`}>
  <div class="container">
    <h1>{pkg.name}</h1>
    <p class="type-badge">{pkg.type}</p>

    {latestMetadata?.description && (
      <p class="description">{latestMetadata.description}</p>
    )}

    <section>
      <h2>Installation</h2>
      {type === 'npm' && (
        <pre><code>npm install {pkg.name}</code></pre>
      )}
      {type === 'container' && (
        <pre><code>docker pull {Astro.url.host}/{user}/{pkg.name}</code></pre>
      )}
    </section>

    <section>
      <h2>Versions</h2>
      <table>
        <thead>
          <tr>
            <th>Version</th>
            <th>Downloads</th>
            <th>Published</th>
          </tr>
        </thead>
        <tbody>
          {versions.map((ver) => (
            <tr>
              <td><a href={`/${user}/packages/${type}/${pkg.name}/${ver.version}`}>{ver.version}</a></td>
              <td>{ver.download_count}</td>
              <td>{new Date(ver.created_at).toLocaleDateString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>

    {latestMetadata?.dependencies && (
      <section>
        <h2>Dependencies</h2>
        <ul>
          {Object.entries(latestMetadata.dependencies).map(([name, version]) => (
            <li>{name}@{version}</li>
          ))}
        </ul>
      </section>
    )}
  </div>
</Layout>
```

## Authentication & Authorization

### Middleware for Package Routes

**File**: `/Users/williamcory/plue/server/middleware/package-auth.ts`

```typescript
import type { Context, Next } from 'hono';

/**
 * Authenticate package operations
 * - Reads: Allow public packages, require auth for private
 * - Writes: Require auth and ownership
 */
export async function packageAuth(c: Context, next: Next) {
  // TODO: Extract token from Authorization header
  // Bearer token, Basic auth, or npm token

  const authHeader = c.req.header('Authorization');
  if (!authHeader) {
    // Public read allowed for now
    return next();
  }

  // Parse Bearer token
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    return c.json({ error: 'Invalid authorization header' }, 401);
  }

  const token = match[1];

  // TODO: Validate token, get user
  // For now, allow all authenticated requests

  return next();
}
```

Apply middleware to package routes:

```typescript
// In server/routes/packages/npm.ts
app.use('*', packageAuth);
```

## Testing

### Manual Testing with NPM

1. **Configure npm to use Plue registry**:
   ```bash
   npm config set registry http://localhost:3000/api/packages/evilrabbit/npm/
   ```

2. **Publish a package**:
   ```bash
   cd /path/to/my-package
   npm publish
   ```

3. **Install a package**:
   ```bash
   npm install my-package
   ```

### Manual Testing with Docker

1. **Login to registry**:
   ```bash
   docker login localhost:3000
   ```

2. **Tag an image**:
   ```bash
   docker tag my-image localhost:3000/evilrabbit/my-image:latest
   ```

3. **Push to registry**:
   ```bash
   docker push localhost:3000/evilrabbit/my-image:latest
   ```

4. **Pull from registry**:
   ```bash
   docker pull localhost:3000/evilrabbit/my-image:latest
   ```

## Implementation Checklist

### Phase 1: Database & Storage

- [ ] Add package tables to schema.sql
- [ ] Create database migration
- [ ] Implement PackageBlobStorage class
- [ ] Create db/packages.ts with CRUD operations
- [ ] Add package types to db/types.ts

### Phase 2: NPM Registry

- [ ] Create NPM metadata types
- [ ] Implement NPM API routes (GET, PUT, DELETE)
- [ ] Test npm publish with sample package
- [ ] Test npm install from registry
- [ ] Implement dist-tags (latest, next, etc.)
- [ ] Add scoped package support (@org/package)

### Phase 3: Container Registry

- [ ] Create container metadata types
- [ ] Implement OCI /v2/ endpoints
- [ ] Implement blob upload (chunked/resumable)
- [ ] Implement manifest upload/download
- [ ] Test docker push
- [ ] Test docker pull
- [ ] Add multi-arch manifest support

### Phase 4: Web UI

- [ ] Create package list page
- [ ] Create package detail page
- [ ] Create version detail page
- [ ] Add package search
- [ ] Display installation instructions
- [ ] Show download statistics

### Phase 5: Authentication

- [ ] Add package authentication middleware
- [ ] Support npm auth tokens
- [ ] Support docker registry auth (WWW-Authenticate)
- [ ] Implement ownership checks
- [ ] Add API token generation

### Phase 6: Advanced Features

- [ ] Package deletion/unpublish
- [ ] Package deprecation
- [ ] Download statistics aggregation
- [ ] Package README rendering
- [ ] Link packages to repositories
- [ ] Webhook notifications on publish
- [ ] Storage quota enforcement

### Phase 7: Polish

- [ ] Add error handling
- [ ] Add logging
- [ ] Optimize database queries
- [ ] Add indexes for performance
- [ ] Clean up unreferenced blobs
- [ ] Add rate limiting

## Reference: Gitea Code Mapping

### Gitea Go → Plue TypeScript Equivalents

| Gitea Go | Plue TypeScript | Purpose |
|----------|----------------|---------|
| `models/packages/package.go` | `db/packages.ts` | Package CRUD |
| `models/packages/package_version.go` | `db/packages.ts` | Version CRUD |
| `models/packages/package_file.go` | `db/packages.ts` | File CRUD |
| `models/packages/package_blob.go` | `db/packages.ts` | Blob CRUD |
| `modules/packages/npm/metadata.go` | `core/packages/npm/types.ts` | NPM types |
| `modules/packages/container/metadata.go` | `core/packages/container/types.ts` | Container types |
| `routers/api/packages/npm/npm.go` | `server/routes/packages/npm.ts` | NPM API |
| `routers/api/packages/container/container.go` | `server/routes/packages/container.ts` | Container API |
| `services/packages/packages.go` | `core/package-service.ts` | Business logic |
| `modules/packages/content_store.go` | `core/package-storage.ts` | Blob storage |

### Key Gitea Patterns to Adopt

1. **Blob Deduplication**: Use SHA256 as primary identifier
2. **Composite Keys**: Support complex file identifiers beyond just filename
3. **Properties System**: Flexible key-value storage for type-specific data
4. **Internal Packages**: Flag for system/auto-generated packages
5. **Semver Compatibility**: Flag packages that follow semantic versioning
6. **Lead File**: Mark the primary file in a version (e.g., main tarball)

## Future Package Types

The database schema supports adding more package types. Here's a preview:

```typescript
// Future: Python/PyPI
interface PyPIMetadata {
  name: string;
  version: string;
  summary?: string;
  description?: string;
  author?: string;
  license?: string;
  requires_python?: string;
  requires_dist?: string[];
}

// Future: Maven
interface MavenMetadata {
  group_id: string;
  artifact_id: string;
  version: string;
  packaging: string; // jar, war, pom, etc.
  dependencies?: Array<{
    group_id: string;
    artifact_id: string;
    version: string;
    scope?: string;
  }>;
}

// Future: Cargo (Rust)
interface CargoMetadata {
  name: string;
  vers: string;
  deps: Array<{
    name: string;
    req: string; // version requirement
    features?: string[];
  }>;
  features?: Record<string, string[]>;
  yanked?: boolean;
}
```

To add a new package type:
1. Add type to `packages.type` CHECK constraint
2. Create metadata type in `core/packages/{type}/types.ts`
3. Implement API routes in `server/routes/packages/{type}.ts`
4. Add UI pages in `ui/pages/[user]/packages/{type}/`

## Notes

- **Use Bun APIs**: `Bun.file()`, `Bun.write()`, not Node fs
- **Stream Large Files**: Use ReadableStream for package downloads
- **Validate Hashes**: Always verify SHA256 on upload
- **Support Scoped NPM**: Handle `@scope/package` correctly
- **OCI Compliance**: Follow spec strictly for Docker compatibility
- **Error Messages**: Return registry-compatible error codes
- **CORS Headers**: Required for browser-based npm clients
- **Content-Type**: Respect Accept headers for manifest format negotiation

## Resources

- [NPM Registry API](https://github.com/npm/registry/blob/master/docs/REGISTRY-API.md)
- [OCI Distribution Spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md)
- [Docker Registry HTTP API V2](https://docs.docker.com/registry/spec/api/)
- [Gitea Packages Source](https://github.com/go-gitea/gitea/tree/main/models/packages)
