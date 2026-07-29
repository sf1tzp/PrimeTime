package device

import (
	"context"

	"github.com/jinzhu/copier"
	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// Devices returns all devices.
func (r *ResolverForDevice) Devices(ctx context.Context) ([]*gqlmodel.Device, error) {
	user := auth.GetUser(ctx)
	var devices []model.Device
	find := r.DB.Where(&model.Device{UserID: user.ID}).Order("active_at DESC").Find(&devices)
	var result []*gqlmodel.Device
	copier.Copy(&result, &devices)
	return result, find.Error
}
