package tag

import (
	"testing"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestGQL_Tags(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	left := db.User(5)
	right := db.User(2)
	left.NewTagDefinition("my tag")
	left.NewTagDefinition("my tag 2")
	left.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z").Tag("my tag", "value")
	left.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z").Tag("my tag", "value").Tag("my tag 2", "v")
	left.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z").Tag("my tag", "value").Tag("my tag 2", "v")
	right.NewTagDefinition("my tag")
	right.NewTagDefinition("my tag 2")
	right.NewTagDefinition("my tag 5")
	right.TimeSpan("2009-06-30T18:30:00Z", "2009-06-30T18:40:00Z").Tag("my tag", "value").Tag("my tag 2", "v")

	resolver := ResolverForTag{DB: db.DB}
	tags, err := resolver.LabelDefinitions(fake.User(left.User.ID))

	require.Nil(t, err)
	expected := []*gqlmodel.LabelDefinition{
		{Key: "my tag", Usages: 3, ValueColors: []*gqlmodel.LabelValueColor{}},
		{Key: "my tag 2", Usages: 2, ValueColors: []*gqlmodel.LabelValueColor{}},
	}
	require.Equal(t, expected, tags)
}
