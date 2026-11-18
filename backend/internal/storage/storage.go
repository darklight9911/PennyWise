// Package storage keeps files (receipts, exports) in Cloudflare R2 through
// its S3 API. The bucket is private: phones only ever get short-lived
// presigned URLs, and uploads go straight to R2, not through the API.
package storage

import (
	"context"
	"errors"
	"time"
)

// Store is what the app needs from object storage.
type Store interface {
	// PresignPut returns a URL that accepts exactly one PUT of this size and
	// content type (both are signed), plus the headers the client must send.
	PresignPut(ctx context.Context, key, contentType string, size int64, ttl time.Duration) (url string, headers map[string]string, err error)
	// PresignGet returns a URL that downloads the object until ttl passes.
	// downloadName, if set, makes browsers save it under that file name.
	PresignGet(ctx context.Context, key, downloadName string, ttl time.Duration) (string, error)
	// Head reports the object's size and type; ErrNotFound if it is missing.
	Head(ctx context.Context, key string) (Object, error)
	// Put stores small server-made files (exports).
	Put(ctx context.Context, key, contentType string, body []byte) error
	// Delete removes one object. A missing object is not an error.
	Delete(ctx context.Context, key string) error
	// DeletePrefix removes every object whose key starts with prefix.
	DeletePrefix(ctx context.Context, prefix string) (int, error)
}

// Object describes a stored file.
type Object struct {
	Size        int64
	ContentType string
}

// ErrNotFound means the object does not exist.
var ErrNotFound = errors.New("storage: object not found")

// Open returns the R2 store, or nil (and no error) when no bucket is set.
func Open(cfg R2Config) (Store, error) {
	if cfg.Bucket == "" {
		return nil, nil
	}
	return NewR2(cfg)
}
