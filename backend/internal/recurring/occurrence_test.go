package recurring

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestOccurrenceIDIsFixedAndV5(t *testing.T) {
	rule := uuid.MustParse("01934f2a-0000-7000-8000-000000000001")
	day := time.Date(2026, 11, 18, 0, 0, 0, 0, time.UTC)
	id := OccurrenceID(rule, day)
	// Pinned value: the phone's test checks the very same string.
	if got := id.String(); got != pinned {
		t.Fatalf("OccurrenceID = %s, want %s (did the namespace change?)", got, pinned)
	}
	if id.Version() != 5 {
		t.Fatalf("version %d, want 5", id.Version())
	}
	if OccurrenceID(rule, day.AddDate(0, 0, 1)) == id {
		t.Fatal("different dates gave the same id")
	}
	// The time of day must not matter, only the date.
	if OccurrenceID(rule, day.Add(13*time.Hour)) != id {
		t.Fatal("time of day changed the id")
	}
}

// Computed once with uuid.NewSHA1; the phone test pins the same value.
const pinned = "91d57823-5af7-50f8-8ba5-02fa79d1df94"
