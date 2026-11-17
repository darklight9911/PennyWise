// Package recurring works out when repeating transactions are due and
// which ID each occurrence has.
package recurring

import (
	"time"

	"github.com/google/uuid"
)

// Namespace for occurrence IDs. NEVER change it: the phone uses the same
// value, and changing it would make both sides create duplicates.
var Namespace = uuid.MustParse("3b8f1c2a-7d4e-4f6a-9c1b-2e5d8a7f6c90")

// OccurrenceID is the fixed ID of the occurrence of rule on date:
// UUIDv5(Namespace, "<rule id>:<YYYY-MM-DD>"). The phone and the server
// compute the same value, so sync merges their copies into one row.
func OccurrenceID(ruleID uuid.UUID, date time.Time) uuid.UUID {
	return uuid.NewSHA1(Namespace, []byte(ruleID.String()+":"+date.Format(time.DateOnly)))
}
