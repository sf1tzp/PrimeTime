package dashboard

import (
	"context"

	"primetime.tools/server/dashboard/convert"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// CreateDashboard creates a dashboard.
func (r *ResolverForDashboard) CreateDashboard(ctx context.Context, name string) (*gqlmodel.Dashboard, error) {
	userID := auth.GetUser(ctx).ID
	dashboard := model.Dashboard{
		UserID: userID,
		Name:   name,
	}

	create := r.DB.Create(&dashboard)
	if create.Error != nil {
		return &gqlmodel.Dashboard{}, create.Error
	}

	return convert.ToExternalDashboard(dashboard)
}
