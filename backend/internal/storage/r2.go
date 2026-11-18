package storage

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/aws/smithy-go"
)

// R2Config holds the bucket settings. Endpoint is optional and overrides
// the R2 endpoint built from AccountID (e.g. a local MinIO).
type R2Config struct {
	AccountID       string
	AccessKeyID     string
	SecretAccessKey string
	Bucket          string
	Endpoint        string
}

// R2 is a Store on Cloudflare R2 (or any S3-compatible service).
type R2 struct {
	client  *s3.Client
	presign *s3.PresignClient
	bucket  string
}

// NewR2 builds the client. Nothing is contacted until the first call.
func NewR2(cfg R2Config) (*R2, error) {
	if cfg.Bucket == "" || cfg.AccessKeyID == "" || cfg.SecretAccessKey == "" {
		return nil, errors.New("storage: bucket and access keys are required")
	}
	endpoint := cfg.Endpoint
	if endpoint == "" {
		if cfg.AccountID == "" {
			return nil, errors.New("storage: R2 account id or an endpoint is required")
		}
		endpoint = fmt.Sprintf("https://%s.r2.cloudflarestorage.com", cfg.AccountID)
	}
	client := s3.New(s3.Options{
		Region:       "auto", // R2 ignores regions; "auto" is what it documents
		Credentials:  credentials.NewStaticCredentialsProvider(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
		BaseEndpoint: aws.String(endpoint),
		UsePathStyle: true,
		// R2 does not support the newer default checksums on every call.
		RequestChecksumCalculation: aws.RequestChecksumCalculationWhenRequired,
		ResponseChecksumValidation: aws.ResponseChecksumValidationWhenRequired,
	})
	return &R2{client: client, presign: s3.NewPresignClient(client), bucket: cfg.Bucket}, nil
}

// PresignPut implements Store. Content-Type and Content-Length are part of
// the signature, so R2 rejects a different file type or size.
func (r *R2) PresignPut(ctx context.Context, key, contentType string, size int64, ttl time.Duration) (string, map[string]string, error) {
	req, err := r.presign.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(r.bucket),
		Key:           aws.String(key),
		ContentType:   aws.String(contentType),
		ContentLength: aws.Int64(size),
	}, s3.WithPresignExpires(ttl))
	if err != nil {
		return "", nil, fmt.Errorf("storage: presign put: %w", err)
	}
	headers := map[string]string{
		"Content-Type":   contentType,
		"Content-Length": strconv.FormatInt(size, 10),
	}
	return req.URL, headers, nil
}

// PresignGet implements Store.
func (r *R2) PresignGet(ctx context.Context, key, downloadName string, ttl time.Duration) (string, error) {
	in := &s3.GetObjectInput{Bucket: aws.String(r.bucket), Key: aws.String(key)}
	if downloadName != "" {
		in.ResponseContentDisposition = aws.String(fmt.Sprintf("attachment; filename=%q", downloadName))
	}
	req, err := r.presign.PresignGetObject(ctx, in, s3.WithPresignExpires(ttl))
	if err != nil {
		return "", fmt.Errorf("storage: presign get: %w", err)
	}
	return req.URL, nil
}

// Head implements Store.
func (r *R2) Head(ctx context.Context, key string) (Object, error) {
	out, err := r.client.HeadObject(ctx, &s3.HeadObjectInput{Bucket: aws.String(r.bucket), Key: aws.String(key)})
	if err != nil {
		if isNotFound(err) {
			return Object{}, ErrNotFound
		}
		return Object{}, fmt.Errorf("storage: head: %w", err)
	}
	return Object{Size: aws.ToInt64(out.ContentLength), ContentType: aws.ToString(out.ContentType)}, nil
}

// Put implements Store.
func (r *R2) Put(ctx context.Context, key, contentType string, body []byte) error {
	_, err := r.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(r.bucket), Key: aws.String(key), ContentType: aws.String(contentType),
		Body: bytes.NewReader(body), ContentLength: aws.Int64(int64(len(body))),
	})
	if err != nil {
		return fmt.Errorf("storage: put: %w", err)
	}
	return nil
}

// Delete implements Store.
func (r *R2) Delete(ctx context.Context, key string) error {
	_, err := r.client.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(r.bucket), Key: aws.String(key)})
	if err != nil && !isNotFound(err) {
		return fmt.Errorf("storage: delete: %w", err)
	}
	return nil
}

// DeletePrefix implements Store, 1,000 keys per request.
func (r *R2) DeletePrefix(ctx context.Context, prefix string) (int, error) {
	if prefix == "" {
		return 0, errors.New("storage: refusing to delete with an empty prefix")
	}
	n := 0
	p := s3.NewListObjectsV2Paginator(r.client, &s3.ListObjectsV2Input{Bucket: aws.String(r.bucket), Prefix: aws.String(prefix)})
	for p.HasMorePages() {
		page, err := p.NextPage(ctx)
		if err != nil {
			return n, fmt.Errorf("storage: list: %w", err)
		}
		if len(page.Contents) == 0 {
			continue
		}
		ids := make([]types.ObjectIdentifier, 0, len(page.Contents))
		for _, o := range page.Contents {
			ids = append(ids, types.ObjectIdentifier{Key: o.Key})
		}
		out, err := r.client.DeleteObjects(ctx, &s3.DeleteObjectsInput{
			Bucket: aws.String(r.bucket), Delete: &types.Delete{Objects: ids, Quiet: aws.Bool(true)},
		})
		if err != nil {
			return n, fmt.Errorf("storage: delete many: %w", err)
		}
		if len(out.Errors) > 0 {
			return n, fmt.Errorf("storage: %d objects not deleted, first: %s", len(out.Errors), aws.ToString(out.Errors[0].Message))
		}
		n += len(ids)
	}
	return n, nil
}

func isNotFound(err error) bool {
	var api smithy.APIError
	if errors.As(err, &api) {
		switch api.ErrorCode() {
		case "NotFound", "NoSuchKey":
			return true
		}
	}
	var re interface{ HTTPStatusCode() int }
	return errors.As(err, &re) && re.HTTPStatusCode() == http.StatusNotFound
}
