package dashboard

import (
	"context"

	"primetime.tools/server/dashboard/convert"
	"primetime.tools/server/dashboard/util"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// RemoveDashboard removes a dashboard.
func (r *ResolverForDashboard) RemoveDashboard(ctx context.Context, id int) (*gqlmodel.Dashboard, error) {
	userID := auth.GetUser(ctx).ID

	dashboard, err := util.FindDashboard(r.DB, userID, id)
	if err != nil {
		return nil, err
	}

	if err := r.DB.Where(&model.Dashboard{UserID: userID, ID: id}).Delete(&model.Dashboard{}).Error; err != nil {
		return &gqlmodel.Dashboard{}, err
	}

	return convert.ToExternalDashboard(dashboard)
}
