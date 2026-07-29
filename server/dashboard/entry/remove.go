package entry

import (
	"context"

	"primetime.tools/server/dashboard/convert"
	"primetime.tools/server/dashboard/util"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// RemoveDashboardEntry removes a dashboard entry.
func (r *ResolverForEntry) RemoveDashboardEntry(ctx context.Context, id int) (*gqlmodel.DashboardEntry, error) {

	userID := auth.GetUser(ctx).ID

	entry, err := util.FindDashboardEntry(r.DB, id)
	if err != nil {
		return nil, err
	}

	if _, err := util.FindDashboard(r.DB, userID, entry.DashboardID); err != nil {
		return nil, err
	}

	remove := r.DB.Delete(&model.DashboardEntry{}, id)
	if remove.Error != nil {
		return &gqlmodel.DashboardEntry{}, remove.Error
	}

	return convert.ToExternalEntry(entry)
}
