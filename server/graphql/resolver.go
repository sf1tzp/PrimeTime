package graphql

import (
	"context"

	"github.com/jinzhu/copier"
	"github.com/jinzhu/gorm"
	"momenttally.com/server/device"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/generated/gqlschema"
	"momenttally.com/server/labelset"
	"momenttally.com/server/model"
	"momenttally.com/server/preference"
	"momenttally.com/server/statistics"
	"momenttally.com/server/tag"
	"momenttally.com/server/timespan"
	"momenttally.com/server/user"
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
		ResolverForPreferences: preference.ResolverForPreferences{
			DB: db,
		},
		ResolverForLabelSet: labelset.ResolverForLabelSet{
			DB: db,
		},
		version: version,
	}
}

type resolver struct {
	user.ResolverForUser
	tag.ResolverForTag
	device.ResolverForDevice
	timespan.ResolverForTimeSpan
	labelset.ResolverForLabelSet
	statistics.ResolverForStatistics
	version model.Version
	preference.ResolverForPreferences
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
