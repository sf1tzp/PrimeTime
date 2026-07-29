// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package model

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
}

// LabelSetMember is one label (key/value pair) inside a label set.
type LabelSetMember struct {
	LabelSetID int `gorm:"type:int REFERENCES label_sets(id) ON DELETE CASCADE"`
	// Position orders the members within the set (ascending).
	Position    int
	Key         string
	StringValue string
}
