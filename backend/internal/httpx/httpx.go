// Package httpx holds small JSON helpers shared by all HTTP handlers.
package httpx

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

// MaxBodyBytes caps request bodies. Sync batches will get their own limit.
const MaxBodyBytes = 1 << 20 // 1 MiB

// WriteJSON writes v as JSON with the given status.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if v != nil {
		_ = json.NewEncoder(w).Encode(v)
	}
}

// ErrorBody is the error shape every endpoint returns.
type ErrorBody struct {
	Error ErrorDetail `json:"error"`
}

// ErrorDetail carries a stable machine-readable code and a human message.
type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// WriteError writes the standard error shape.
func WriteError(w http.ResponseWriter, status int, code, message string) {
	WriteJSON(w, status, ErrorBody{Error: ErrorDetail{Code: code, Message: message}})
}

// DecodeJSON reads a JSON body into dst. It rejects unknown fields, bodies
// over MaxBodyBytes and trailing data, and writes a 400 itself on failure.
// It returns false when the handler should stop.
func DecodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	return DecodeJSONLimit(w, r, dst, MaxBodyBytes)
}

// DecodeJSONLimit is DecodeJSON with a custom body size limit.
func DecodeJSONLimit(w http.ResponseWriter, r *http.Request, dst any, limit int64) bool {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	if err := dec.Decode(dst); err != nil {
		var maxErr *http.MaxBytesError
		msg := "request body is not valid JSON"
		switch {
		case errors.As(err, &maxErr):
			WriteError(w, http.StatusRequestEntityTooLarge, "body_too_large", "request body is too large")
			return false
		case errors.Is(err, io.EOF):
			msg = "request body is empty"
		default:
			var typeErr *json.UnmarshalTypeError
			if errors.As(err, &typeErr) {
				msg = fmt.Sprintf("field %q has the wrong type", typeErr.Field)
			}
		}
		WriteError(w, http.StatusBadRequest, "invalid_json", msg)
		return false
	}
	if dec.More() {
		WriteError(w, http.StatusBadRequest, "invalid_json", "request body must contain one JSON object")
		return false
	}
	return true
}
