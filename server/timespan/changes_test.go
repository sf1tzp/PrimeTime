// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package timespan

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
	"momenttally.com/server/test"
	"momenttally.com/server/test/fake"
)

// clockAt pins the sync clock to a fixed RFC3339 instant, restoring the
// test default (the zero time, see syncclock_test.go) when the test ends.
func clockAt(t *testing.T, value string) {
	instant := test.Time(value)
	syncNow = func() time.Time { return instant }
	t.Cleanup(func() { syncNow = func() time.Time { return time.Time{} } })
}

func changesSince(t *testing.T, resolver *ResolverForTimeSpan, userID int, since string, afterID int, limit *int) *gqlmodel.TimeSpanChanges {
	changes, err := resolver.TimeSpanChanges(fake.User(userID), test.ModelTimeUTC(since), afterID, limit)
	require.Nil(t, err)
	return changes
}

func spanIDs(changes *gqlmodel.TimeSpanChanges) []int {
	ids := []int{}
	for _, span := range changes.TimeSpans {
		ids = append(ids, span.ID)
	}
	return ids
}

func Test_Changes_emptyFeed(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	changes := changesSince(t, resolver, 5, "2020-01-01T00:00:00Z", 0, nil)
	require.Empty(t, changes.TimeSpans)
	require.Empty(t, changes.Deleted)
	require.False(t, changes.HasMore)
}

func Test_Changes_returnsWritesAfterCheckpoint_ordered(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	_, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "first")
	require.Nil(t, err)
	clockAt(t, "2020-01-01T11:00:00Z")
	_, err = resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T08:00:00Z"), nil, nil, "second")
	require.Nil(t, err)

	// From the epoch: both, ordered by updatedAt (not by start).
	changes := changesSince(t, resolver, 5, "1970-01-01T00:00:00Z", 0, nil)
	require.Equal(t, []int{1, 2}, spanIDs(changes))
	require.Equal(t, test.Time("2020-01-01T10:00:00Z"), changes.TimeSpans[0].UpdatedAt.UTC())
	require.False(t, changes.HasMore)

	// From the first span's checkpoint: only the second.
	changes = changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", 1, nil)
	require.Equal(t, []int{2}, spanIDs(changes))

	// From the head: nothing.
	changes = changesSince(t, resolver, 5, "2020-01-01T11:00:00Z", 2, nil)
	require.Empty(t, changes.TimeSpans)
	require.False(t, changes.HasMore)
}

func Test_Changes_updateReappearsInFeed(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	created, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "note")
	require.Nil(t, err)

	// Past the create checkpoint the span is gone from the feed...
	require.Empty(t, changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", created.ID, nil).TimeSpans)

	// ...until an update bumps it back in.
	clockAt(t, "2020-01-01T12:00:00Z")
	_, err = resolver.UpdateTimeSpan(fake.User(5), created.ID, test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, nil, "edited")
	require.Nil(t, err)
	changes := changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", created.ID, nil)
	require.Equal(t, []int{created.ID}, spanIDs(changes))
	require.Equal(t, "edited", changes.TimeSpans[0].Note)
	require.Equal(t, test.Time("2020-01-01T12:00:00Z"), changes.TimeSpans[0].UpdatedAt.UTC())
}

func Test_Changes_stopBumpsCheckpoint(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	created, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "")
	require.Nil(t, err)

	clockAt(t, "2020-01-01T10:30:00Z")
	_, err = resolver.StopTimeSpan(fake.User(5), created.ID, test.ModelTime("2020-01-01T10:15:00Z"))
	require.Nil(t, err)

	changes := changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", created.ID, nil)
	require.Equal(t, []int{created.ID}, spanIDs(changes))
	require.NotNil(t, changes.TimeSpans[0].End)
}

func Test_Changes_paging_tieBreaksOnID(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	// Five spans written within the same second — the worst case for a
	// time-only checkpoint.
	clockAt(t, "2020-01-01T10:00:00Z")
	for i := 0; i < 5; i++ {
		_, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "")
		require.Nil(t, err)
	}

	limit := 2
	page1 := changesSince(t, resolver, 5, "1970-01-01T00:00:00Z", 0, &limit)
	require.Equal(t, []int{1, 2}, spanIDs(page1))
	require.True(t, page1.HasMore)

	// Continue from the last span's (updatedAt, id): the same second, so
	// only the afterId tie-break can advance the walk.
	page2 := changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", 2, &limit)
	require.Equal(t, []int{3, 4}, spanIDs(page2))
	require.True(t, page2.HasMore)

	page3 := changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", 4, &limit)
	require.Equal(t, []int{5}, spanIDs(page3))
	require.False(t, page3.HasMore)
}

func Test_Changes_removeDeliversTombstone(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	created, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "")
	require.Nil(t, err)
	_, err = resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:30:00Z"), nil, nil, "")
	require.Nil(t, err)

	clockAt(t, "2020-01-01T11:00:00Z")
	_, err = resolver.RemoveTimeSpan(fake.User(5), created.ID)
	require.Nil(t, err)

	changes := changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", 2, nil)
	require.Empty(t, changes.TimeSpans)
	require.Len(t, changes.Deleted, 1)
	require.Equal(t, created.ID, changes.Deleted[0].ID)
	require.Equal(t, test.Time("2020-01-01T11:00:00Z"), changes.Deleted[0].DeletedAt.UTC())

	// `deleted` is >= since (never missed, re-delivery is harmless).
	require.Len(t, changesSince(t, resolver, 5, "2020-01-01T11:00:00Z", 0, nil).Deleted, 1)
	// Strictly later checkpoints drop it.
	require.Empty(t, changesSince(t, resolver, 5, "2020-01-01T11:00:01Z", 0, nil).Deleted)
}

func Test_Changes_staleTombstone_suppressedWhenIDLive(t *testing.T) {
	// gorm declares sqlite ids AUTOINCREMENT, so ids are normally never
	// reused. The stale-tombstone guards are defensive — other dialects, a
	// restored backup — so simulate the state directly: a tombstone whose
	// id is a live span.
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	created, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "live")
	require.Nil(t, err)
	require.Nil(t, db.Create(&model.TimeSpanTombstone{
		TimeSpanID:   created.ID,
		UserID:       5,
		DeletedAtUTC: test.Time("2020-01-01T09:59:00Z"),
	}).Error)

	// The live id must not be reported deleted.
	changes := changesSince(t, resolver, 5, "1970-01-01T00:00:00Z", 0, nil)
	require.Empty(t, changes.Deleted)
	require.Equal(t, []int{created.ID}, spanIDs(changes))

	// Deleting the span must not collide with the stale tombstone (the
	// tombstone upsert replaces it), and the deletion then surfaces.
	clockAt(t, "2020-01-01T13:00:00Z")
	_, err = resolver.RemoveTimeSpan(fake.User(5), created.ID)
	require.Nil(t, err)
	changes = changesSince(t, resolver, 5, "1970-01-01T00:00:00Z", 0, nil)
	require.Len(t, changes.Deleted, 1)
	require.Equal(t, test.Time("2020-01-01T13:00:00Z"), changes.Deleted[0].DeletedAt.UTC())
}

func Test_Changes_scopedToUser(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	db.User(6)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	mine, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "")
	require.Nil(t, err)
	other, err := resolver.CreateTimeSpan(fake.User(6), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "")
	require.Nil(t, err)
	clockAt(t, "2020-01-01T11:00:00Z")
	_, err = resolver.RemoveTimeSpan(fake.User(6), other.ID)
	require.Nil(t, err)

	changes := changesSince(t, resolver, 5, "1970-01-01T00:00:00Z", 0, nil)
	require.Equal(t, []int{mine.ID}, spanIDs(changes))
	require.Empty(t, changes.Deleted)
}

func Test_Changes_replaceLabelsBumpsAffectedSpans(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(5)
	user.NewTagDefinition("proj")
	user.NewTagDefinition("area")
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	labels := []*gqlmodel.InputLabel{{Key: "proj", Value: "old"}}
	created, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, labels, "")
	require.Nil(t, err)

	clockAt(t, "2020-01-01T12:00:00Z")
	_, err = resolver.ReplaceTimeSpanLabels(fake.User(5),
		gqlmodel.InputLabel{Key: "proj", Value: "old"},
		gqlmodel.InputLabel{Key: "area", Value: "new"},
		gqlmodel.InputReplaceOptions{Override: gqlmodel.OverrideModeOverride})
	require.Nil(t, err)

	changes := changesSince(t, resolver, 5, "2020-01-01T10:00:00Z", created.ID, nil)
	require.Equal(t, []int{created.ID}, spanIDs(changes))
	require.Equal(t, []*gqlmodel.Label{{Key: "area", Value: "new"}}, changes.TimeSpans[0].Labels)
}

func Test_Changes_limitDefaultsAndCaps(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	resolver := &ResolverForTimeSpan{DB: db.DB}

	clockAt(t, "2020-01-01T10:00:00Z")
	for i := 0; i < changesMaxLimit+1; i++ {
		_, err := resolver.CreateTimeSpan(fake.User(5), test.ModelTime("2020-01-01T09:00:00Z"), nil, nil, "")
		require.Nil(t, err)
	}

	// nil limit: server default page size.
	changes := changesSince(t, resolver, 5, "1970-01-01T00:00:00Z", 0, nil)
	require.Len(t, changes.TimeSpans, changesMaxLimit)
	require.True(t, changes.HasMore)

	// An over-large limit is capped.
	huge := changesMaxLimit * 10
	changes = changesSince(t, resolver, 5, "1970-01-01T00:00:00Z", 0, &huge)
	require.Len(t, changes.TimeSpans, changesMaxLimit)
}
