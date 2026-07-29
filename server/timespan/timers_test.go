package timespan

import (
	"testing"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestTimers(t *testing.T) {
	db := test.InMemoryDB(t)
	db.User(5)
	db.Create(timeSpan1)
	db.Create(runningTimeSpan)
	defer db.Close()

	resolver := ResolverForTimeSpan{DB: db.DB}
	timeSpans, err := resolver.Timers(fake.User(5))
	require.NoError(t, err)

	expected := []*gqlmodel.TimeSpan{&modelRunningTimeSpan}
	require.Equal(t, expected, timeSpans)
}
