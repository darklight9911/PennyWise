package storage

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"
)

// Memory is an in-memory Store for tests. Presigned URLs are fake
// "memory://" links; tests "upload" with PutFile.
type Memory struct {
	mu      sync.Mutex
	objects map[string]memObject
}

type memObject struct {
	contentType string
	body        []byte
}

// NewMemory creates an empty store.
func NewMemory() *Memory { return &Memory{objects: map[string]memObject{}} }

// PutFile stores an object as if a phone had uploaded it.
func (m *Memory) PutFile(key, contentType string, body []byte) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.objects[key] = memObject{contentType: contentType, body: append([]byte(nil), body...)}
}

// Has reports whether key exists.
func (m *Memory) Has(key string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, ok := m.objects[key]
	return ok
}

// Body returns an object's bytes (nil if missing).
func (m *Memory) Body(key string) []byte {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.objects[key].body
}

// Keys lists stored keys with the prefix.
func (m *Memory) Keys(prefix string) []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []string
	for k := range m.objects {
		if strings.HasPrefix(k, prefix) {
			out = append(out, k)
		}
	}
	return out
}

// PresignPut implements Store.
func (m *Memory) PresignPut(_ context.Context, key, contentType string, size int64, ttl time.Duration) (string, map[string]string, error) {
	return fmt.Sprintf("memory://put/%s?ttl=%s", key, ttl), map[string]string{
		"Content-Type": contentType, "Content-Length": fmt.Sprint(size),
	}, nil
}

// PresignGet implements Store.
func (m *Memory) PresignGet(_ context.Context, key, downloadName string, ttl time.Duration) (string, error) {
	return fmt.Sprintf("memory://get/%s?name=%s&ttl=%s", key, downloadName, ttl), nil
}

// Head implements Store.
func (m *Memory) Head(_ context.Context, key string) (Object, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	o, ok := m.objects[key]
	if !ok {
		return Object{}, ErrNotFound
	}
	return Object{Size: int64(len(o.body)), ContentType: o.contentType}, nil
}

// Put implements Store.
func (m *Memory) Put(_ context.Context, key, contentType string, body []byte) error {
	m.PutFile(key, contentType, body)
	return nil
}

// Delete implements Store.
func (m *Memory) Delete(_ context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.objects, key)
	return nil
}

// DeletePrefix implements Store.
func (m *Memory) DeletePrefix(_ context.Context, prefix string) (int, error) {
	if prefix == "" {
		return 0, fmt.Errorf("storage: refusing to delete with an empty prefix")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	n := 0
	for k := range m.objects {
		if strings.HasPrefix(k, prefix) {
			delete(m.objects, k)
			n++
		}
	}
	return n, nil
}
