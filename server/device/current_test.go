package device

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
	"momenttally.com/server/test"
	"momenttally.com/server/test/fake"
)

func TestGQL_CurrentDevice_withDevice(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()

	device := &model.Device{
		ID:        2,
		Name:      "Browser",
		Token:     "abcd",
		UserID:    2,
		CreatedAt: test.Time("2004-06-30T18:30:00Z"),
		ActiveAt:  test.Time("2015-06-30T18:30:00Z"),
		Type:      model.TypeNoExpiry,
	}

	resolver := ResolverForDevice{DB: db.DB}
	result, err := resolver.CurrentDevice(fake.Device(device))

	require.Nil(t, err)
	expected := &gqlmodel.Device{
		ID:        2,
		Name:      "Browser",
		CreatedAt: test.ModelTimeUTC("2004-06-30T18:30:00Z"),
		ActiveAt:  test.ModelTimeUTC("2015-06-30T18:30:00Z"),
		Type:      gqlmodel.DeviceTypeNoExpiry,
	}

	require.Equal(t, expected, result)
}

func TestGQL_CurrentDevice_noDevice(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()

	resolver := ResolverForDevice{DB: db.DB}
	result, err := resolver.CurrentDevice(context.Background())

	require.Nil(t, err)

	require.Nil(t, result)
}
