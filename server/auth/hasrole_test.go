package auth_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/test/fake"
)

var (
	successResp = struct{}{}
)

func TestHasRole_requiredUser_givenAdmin_succeeds(t *testing.T) {
	res, err := auth.HasRole()(fake.UserWithPerm(1, true), nil, noop, gqlmodel.RoleUser)
	assert.Nil(t, err)
	assert.Equal(t, successResp, res)
}

func TestHasRole_requiredAdmin_givenAdmin_succeeds(t *testing.T) {
	res, err := auth.HasRole()(fake.UserWithPerm(1, true), nil, noop, gqlmodel.RoleAdmin)
	assert.Nil(t, err)
	assert.Equal(t, successResp, res)
}

func TestHasRole_requiredUser_givenUser_succeeds(t *testing.T) {
	res, err := auth.HasRole()(fake.UserWithPerm(1, false), nil, noop, gqlmodel.RoleUser)
	assert.Nil(t, err)
	assert.Equal(t, successResp, res)
}

func TestHasRole_requiredAdmin_givenUser_fails(t *testing.T) {
	res, err := auth.HasRole()(fake.UserWithPerm(1, false), nil, noop, gqlmodel.RoleAdmin)
	assert.Nil(t, res)
	assert.EqualError(t, err, "permission denied")
}

func TestHasRole_requiredAdmin_noUserGiven_fails(t *testing.T) {
	res, err := auth.HasRole()(context.Background(), nil, noop, gqlmodel.RoleAdmin)
	assert.Nil(t, res)
	assert.EqualError(t, err, "you need to login")
}

func TestHasRole_requiredUser_noUserGiven_fails(t *testing.T) {
	res, err := auth.HasRole()(context.Background(), nil, noop, gqlmodel.RoleUser)
	assert.Nil(t, res)
	assert.EqualError(t, err, "you need to login")
}

func noop(context.Context) (res interface{}, err error) {
	return successResp, nil
}
