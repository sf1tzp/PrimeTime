package user

import (
	"context"
	"fmt"

	"github.com/jinzhu/copier"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/labelset"
	"primetime.tools/server/model"
)

// CreateUser creates a user.
func (r *ResolverForUser) CreateUser(ctx context.Context, name string, pass string, admin bool) (*gqlmodel.User, error) {
	newUser := &model.User{
		Name:  name,
		Pass:  createPassword(pass, r.PassStrength),
		Admin: admin,
	}

	if !r.DB.Where("name = ?", newUser.Name).Find(&model.User{}).RecordNotFound() {
		return nil, fmt.Errorf("user with name '%s' does already exist", newUser.Name)
	}

	if err := r.DB.Create(&newUser).Error; err != nil {
		return nil, err
	}

	// New users start with the default label set collection (PrimeTime v1).
	if err := labelset.SeedDefaultLabelSets(r.DB, newUser.ID); err != nil {
		return nil, err
	}

	gqlUser := &gqlmodel.User{}
	copier.Copy(gqlUser, newUser)
	return gqlUser, nil
}
