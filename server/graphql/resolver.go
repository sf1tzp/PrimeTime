package graphql

import (
	"context"

	"primetime.tools/server/dashboard"
	"primetime.tools/server/setting"

	"github.com/jinzhu/copier"
	"github.com/jinzhu/gorm"
	"primetime.tools/server/device"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/generated/gqlschema"
	"primetime.tools/server/model"
	"primetime.tools/server/statistics"
	"primetime.tools/server/tag"
	"primetime.tools/server/timespan"
	"primetime.tools/server/user"
)

// NewResolver combines all resolvers to a resolver root.
func NewResolver(db *gorm.DB, passStrength int, version model.Version) gqlschema.ResolverRoot {
	return &resolver{
		ResolverForUser: user.ResolverForUser{
			DB:           db,
			PassStrength: passStrength,
		},
		ResolverForTag: tag.ResolverForTag{
			DB: db,
		},
		ResolverForDevice: device.ResolverForDevice{
			DB: db,
		},
		ResolverForTimeSpan: timespan.ResolverForTimeSpan{
			DB: db,
		},
		ResolverForStatistics: statistics.ResolverForStatistics{
			DB: db,
		},
		ResolverForSettings: setting.ResolverForSettings{
			DB: db,
		},
		ResolverForDashboard: dashboard.NewResolverForDashboard(db),
		version:              version,
	}
}

type resolver struct {
	user.ResolverForUser
	tag.ResolverForTag
	device.ResolverForDevice
	timespan.ResolverForTimeSpan
	statistics.ResolverForStatistics
	version model.Version
	setting.ResolverForSettings
	dashboard.ResolverForDashboard
}

func (r *resolver) RootMutation() gqlschema.RootMutationResolver {
	return r
}

func (r *resolver) RootQuery() gqlschema.RootQueryResolver {
	return r
}

func (r *resolver) Version(ctx context.Context) (*gqlmodel.Version, error) {
	gql := &gqlmodel.Version{}
	copier.Copy(gql, r.version)
	return gql, nil
}
