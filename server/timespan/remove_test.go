package timespan

import (
	"testing"

	"momenttally.com/server/generated/gqlmodel"

	"github.com/stretchr/testify/require"
	"momenttally.com/server/model"
	"momenttally.com/server/test"
	"momenttally.com/server/test/fake"
)

func TestRemoveTimeSpan_succeeds_removesTimeSpan(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(3)
	ts := user.TimeSpan("2019-06-11T18:00:00Z", "2019-06-11T18:00:00Z")
	ts.Tag("hello", "world")

	resolver := ResolverForTimeSpan{DB: db.DB}
	actual, err := resolver.RemoveTimeSpan(fake.User(3), ts.TimeSpan.ID)
	require.NoError(t, err)
	expected := &gqlmodel.TimeSpan{
		ID:    ts.TimeSpan.ID,
		Start: test.ModelTime("2019-06-11T18:00:00Z"),
		End:   test.ModelTimeP("2019-06-11T18:00:00Z"),
		Labels: []*gqlmodel.Label{
			{Key: "hello", Value: "world"},
		},
	}
	require.Equal(t, expected, actual)
	assertTimeSpanCount(t, db, 0)
}

func TestRemoveTimeSpan_succeeds_removesTags(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(3)
	ts := user.TimeSpan("2019-06-11T18:00:00Z", "2019-06-11T18:00:00Z")
	ts.Tag("hello", "world")

	resolver := ResolverForTimeSpan{DB: db.DB}
	_, err := resolver.RemoveTimeSpan(fake.User(3), ts.TimeSpan.ID)
	require.NoError(t, err)

	ts.AssertHasTag("hello", "world", false)
}

func TestRemoveTimeSpan_fails_notExistingTimeSpan(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(3)

	resolver := ResolverForTimeSpan{DB: db.DB}
	_, err := resolver.RemoveTimeSpan(fake.User(3), 5)
	require.EqualError(t, err, "timespan with id 5 does not exist")
}

func TestRemoveTimeSpan_fails_noPermission(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(3)
	db.User(5)
	db.Create(&model.TimeSpan{
		StartUserTime: test.Time("2019-06-11T18:00:00Z"),
		StartUTC:      test.Time("2019-06-11T18:00:00Z"),
		EndUserTime:   nil,
		EndUTC:        nil,
		OffsetUTC:     0,
		ID:            1,
		UserID:        3,
	})

	resolver := ResolverForTimeSpan{DB: db.DB}
	_, err := resolver.RemoveTimeSpan(fake.User(5), 1)
	require.EqualError(t, err, "timespan with id 1 does not exist")
}
