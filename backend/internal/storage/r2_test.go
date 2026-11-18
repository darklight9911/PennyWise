package storage

import (
	"context"
	"net/url"
	"strings"
	"testing"
	"time"
)

// Presigning is local (no network), so the signed parts can be checked.
func TestPresignPutSignsTypeAndSize(t *testing.T) {
	r, err := NewR2(R2Config{AccountID: "acct", AccessKeyID: "AKIDEXAMPLE", SecretAccessKey: "secret-example", Bucket: "pw"})
	if err != nil {
		t.Fatal(err)
	}
	raw, headers, err := r.PresignPut(context.Background(), "receipts/u/r.jpg", "image/jpeg", 1234, 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	u, _ := url.Parse(raw)
	if u.Host != "acct.r2.cloudflarestorage.com" || u.Path != "/pw/receipts/u/r.jpg" {
		t.Errorf("url %s", raw)
	}
	q := u.Query()
	signed := q.Get("X-Amz-SignedHeaders")
	for _, h := range []string{"content-length", "content-type", "host"} {
		if !strings.Contains(signed, h) {
			t.Errorf("%s is not signed: %s", h, signed)
		}
	}
	if q.Get("X-Amz-Expires") != "300" {
		t.Errorf("expires %s", q.Get("X-Amz-Expires"))
	}
	if headers["Content-Type"] != "image/jpeg" || headers["Content-Length"] != "1234" {
		t.Errorf("headers %v", headers)
	}

	get, err := r.PresignGet(context.Background(), "exports/u/e.csv", "pennywise.csv", time.Minute)
	if err != nil || !strings.Contains(get, "response-content-disposition=attachment") {
		t.Errorf("get url %s %v", get, err)
	}
	if _, err := r.DeletePrefix(context.Background(), ""); err == nil {
		t.Error("empty prefix must be refused")
	}
}

func TestNewR2NeedsSettings(t *testing.T) {
	if _, err := NewR2(R2Config{Bucket: "b", AccessKeyID: "a", SecretAccessKey: "s"}); err == nil {
		t.Error("no account id and no endpoint: want error")
	}
}
