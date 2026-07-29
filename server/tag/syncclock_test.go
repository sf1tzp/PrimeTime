// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package tag

import "time"

// Most tests in this package assert exact struct equality against rows and
// externals with zero-valued sync timestamps; pin the sync clock to the zero
// time so they stay exact. Tests that exercise sync behaviour override
// syncNow themselves (and restore it).
func init() { syncNow = func() time.Time { return time.Time{} } }
