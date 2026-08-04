// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package model

import "time"

// LabelSet is a named, ordered, launchable combination of labels (the
// launcher cards in the PrimeTime app). Sets belong to a user; rows with a
// nil UserID and DefaultCollection set are templates — the "default
// collection" copied to every newly created user.
type LabelSet struct {
	ID int `gorm:"primary_key;unique_index;AUTO_INCREMENT"`
	// UserID is nil for template sets in the default collection.
	UserID *int `gorm:"type:int REFERENCES users(id) ON DELETE CASCADE"`
	Name   string
	// SymbolName is the SF Symbol shown on the set's launcher card.
	SymbolName string
	// Position orders a user's sets in the launcher (ascending).
	Position int
	// DefaultCollection marks a template set that is copied to new users.
	DefaultCollection bool
	Members           []LabelSetMember
	// UpdatedAtUTC is the server time of the last write (whole seconds),
	// for last-writer-wins sync. Managed explicitly, not by gorm.
	UpdatedAtUTC time.Time
}

// LabelSetMember is one label (key/value pair) inside a label set.
type LabelSetMember struct {
	LabelSetID int `gorm:"type:int REFERENCES label_sets(id) ON DELETE CASCADE"`
	// Position orders the members within the set (ascending), separately
	// for regular and quick members.
	Position    int
	Key         string
	StringValue string
	// Quick marks a quick label — a one-click refinement offered when
	// hovering the set in the app — rather than a regular member. Rows
	// that predate the column are backfilled to false (see database.New).
	Quick bool
}
