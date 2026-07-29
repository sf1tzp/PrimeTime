package dashboard

import (
	"context"

	"primetime.tools/server/dashboard/convert"

	"primetime.tools/server/dashboard/util"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// UpdateDashboard updates a dashboard.
func (r *ResolverForDashboard) UpdateDashboard(ctx context.Context, id int, name string) (*gqlmodel.Dashboard, error) {
	userID := auth.GetUser(ctx).ID

	dashboard, err := util.FindDashboard(r.DB, userID, id)
	if err != nil {
		return nil, err
	}

	dashboard.Name = name

	save := r.DB.Save(dashboard)

	if save.Error != nil {
		return nil, save.Error
	}

	var entries []model.DashboardEntry
	if err := r.DB.Where(&model.DashboardEntry{DashboardID: dashboard.ID}).Find(&entries).Error; err != nil {
		return nil, err
	}
	dashboard.Entries = entries

	var ranges []model.DashboardRange
	if err := r.DB.Where(&model.DashboardRange{DashboardID: dashboard.ID}).Find(&ranges).Error; err != nil {
		return nil, err
	}
	dashboard.Ranges = ranges

	return convert.ToExternalDashboard(dashboard)
}
