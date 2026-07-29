// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

// Package labelset implements PrimeTime v1 label sets: per-user, named,
// ordered, launchable combinations of labels (the launcher cards in the
// PrimeTime app), plus the default collection new users are seeded with.
package labelset

import "github.com/jinzhu/gorm"

// ResolverForLabelSet resolves label set specific things.
type ResolverForLabelSet struct {
	DB *gorm.DB
}
