package tag

import (
	"testing"

	"github.com/magiconair/properties/assert"
	"github.com/stretchr/testify/require"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestUpdate_withKey(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	left := db.User(5)
	right := db.User(2)
	left.NewTagDefinition("coolio")
	right.NewTagDefinition("coolio")
	leftTs := left.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z")
	leftTs.Tag("coolio", "mama")
	rightTs := right.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z")
	rightTs.Tag("coolio", "mama")

	resolver := ResolverForTag{DB: db.DB}
	newTagName := "mega"
	tag, err := resolver.UpdateLabelDefinition(fake.User(left.User.ID), "coolio", &newTagName, "#abc")
	require.NoError(t, err)
	require.Equal(t, &gqlmodel.LabelDefinition{
		Color:       "#abc",
		Key:         "mega",
		ValueColors: []*gqlmodel.LabelValueColor{},
	}, tag)
	left.AssertHasTagDefinition("coolio", false).AssertHasTagDefinition("mega", true)
	right.AssertHasTagDefinition("coolio", true).AssertHasTagDefinition("mega", false)
	leftTs.AssertHasTag("mega", "mama", true).AssertHasTag("coolio", "mama", false)
	rightTs.AssertHasTag("coolio", "mama", true).AssertHasTag("mega", "mama", false)
}

func TestUpdate_lowercases(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(5)
	user.NewTagDefinition("coolio")
	ts := user.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z")
	ts.Tag("coolio", "mama")

	resolver := ResolverForTag{DB: db.DB}
	newTagName := "Mega"
	tag, err := resolver.UpdateLabelDefinition(fake.User(user.User.ID), "coolio", &newTagName, "#abc")
	require.NoError(t, err)
	require.Equal(t, &gqlmodel.LabelDefinition{
		Color:       "#abc",
		Key:         "mega",
		ValueColors: []*gqlmodel.LabelValueColor{},
	}, tag)
	user.AssertHasTagDefinition("coolio", false).AssertHasTagDefinition("mega", true)
	ts.AssertHasTag("mega", "mama", true).AssertHasTag("coolio", "mama", false)
}

func TestUpdate_disallow_space(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(5)
	user.NewTagDefinition("coolio")

	resolver := ResolverForTag{DB: db.DB}
	newTagName := "the coolio"
	_, err := resolver.UpdateLabelDefinition(fake.User(user.User.ID), "coolio", &newTagName, "#abc")
	require.EqualError(t, err, "tag must not contain spaces")
}

func TestUpdate_withoutKey(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	left := db.User(5)
	right := db.User(2)
	left.NewTagDefinition("coolio")
	right.NewTagDefinition("coolio")
	leftTs := left.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z")
	leftTs.Tag("coolio", "mama")
	rightTs := right.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z")
	rightTs.Tag("coolio", "mama")

	resolver := ResolverForTag{DB: db.DB}
	tag, err := resolver.UpdateLabelDefinition(fake.User(left.User.ID), "coolio", nil, "#abc")
	require.NoError(t, err)
	assert.Equal(t, &gqlmodel.LabelDefinition{
		Color:       "#abc",
		Key:         "coolio",
		ValueColors: []*gqlmodel.LabelValueColor{},
	}, tag)
}

func TestUpdate_noPermissions(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	left := db.User(5)
	right := db.User(2)
	right.NewTagDefinition("coolio")
	rightTs := right.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z")
	rightTs.Tag("coolio", "mama")

	resolver := ResolverForTag{DB: db.DB}
	_, err := resolver.UpdateLabelDefinition(fake.User(left.User.ID), "coolio", nil, "#abc")
	require.EqualError(t, err, "tag with key 'coolio' does not exist")
	right.AssertHasTagDefinition("coolio", true)
}
