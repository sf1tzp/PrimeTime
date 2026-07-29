package setting

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/model"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestGet_noUser(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()

	settings, err := Get(context.Background(), db.DB)
	require.NoError(t, err)
	require.Equal(t, model.ThemeGruvboxDark, settings.Theme)
}

func TestGet_user_noSettings(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(1)

	settings, err := Get(fake.User(1), db.DB)
	require.NoError(t, err)
	require.Equal(t, model.ThemeGruvboxDark, settings.Theme)
}

func TestGet_user(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(1)
	db.Save(&model.UserSetting{
		UserID:            1,
		Theme:             model.ThemeGruvboxLight,
		DateLocale:        model.DateLocaleGerman,
		FirstDayOfTheWeek: time.Sunday.String(),
	})

	settings, err := Get(fake.User(1), db.DB)
	require.NoError(t, err)
	require.Equal(t, model.ThemeGruvboxLight, settings.Theme)
}
