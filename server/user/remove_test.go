package user

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"momenttally.com/server/model"
	"momenttally.com/server/test"
)

func TestGQL_RemoveUser_succeeds_removesUser(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.NewUserPass(1, "jmattheis", unicornPW, true)

	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	_, err := resolver.RemoveUser(context.Background(), 1)

	require.Nil(t, err)
	assertUserCount(t, db, 0)
}

func TestGQL_RemoveUser_succeeds_removesDevices(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(1)
	user.NewDevice(2, "abc", "devicename")
	other := db.User(2)
	other.NewDevice(5, "abcx", "devicename")

	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	_, err := resolver.RemoveUser(context.Background(), 1)

	require.Nil(t, err)
	user.AssertHasDevice("devicename", false).AssertExists(false)
	other.AssertExists(true).AssertHasDevice("devicename", true)
}

func TestGQL_RemoveUser_succeeds_removesTags(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(1)
	user.NewTagDefinition("oops")
	other := db.User(2)
	other.NewTagDefinition("oops")

	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	_, err := resolver.RemoveUser(context.Background(), 1)

	require.Nil(t, err)
	user.AssertExists(false).AssertHasTagDefinition("oops", false)
	other.AssertExists(true).AssertHasTagDefinition("oops", true)
}

func TestGQL_RemoveUser_succeeds_removesTimeSpans(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(1)
	other := db.User(2)
	ts := user.TimeSpan("2019-06-11T18:00:00Z", "2019-06-11T18:00:00Z")
	ts.Tag("hello", "world")
	otherTs := other.TimeSpan("2019-06-11T18:00:00Z", "2019-06-11T18:00:00Z")
	otherTs.Tag("hello", "world")

	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	_, err := resolver.RemoveUser(context.Background(), 1)

	require.Nil(t, err)
	ts.AssertExists(false).AssertHasTag("hello", "world", false)
	otherTs.AssertExists(true).AssertHasTag("hello", "world", true)
}

func TestGQL_RemoveUser_succeeds_removesLabelSets(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(1)
	db.User(2)
	userID, otherID := 1, 2
	db.Create(&model.LabelSet{UserID: &userID, Name: "cool", Members: []model.LabelSetMember{{Position: 0, Key: "a", StringValue: "b"}}})
	db.Create(&model.LabelSet{UserID: &otherID, Name: "cool", Members: []model.LabelSetMember{{Position: 0, Key: "a", StringValue: "b"}}})

	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	_, err := resolver.RemoveUser(context.Background(), 1)

	require.Nil(t, err)
	count := new(int)
	db.Model(new(model.LabelSet)).Count(count)
	require.Equal(t, 1, *count)
	db.Model(new(model.LabelSetMember)).Count(count)
	require.Equal(t, 1, *count)
}

func TestGQL_RemoveUser_fails_notExistingUser(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.NewUserPass(1, "jmattheis", unicornPW, true)

	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	_, err := resolver.RemoveUser(context.Background(), 3)

	require.EqualError(t, err, "user with id 3 does not exist")
	assertUserCount(t, db, 1)
}
