package convert

import (
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// InternalInterval converts interval.
func InternalInterval(interval gqlmodel.StatsInterval) model.Interval {
	switch interval {
	case gqlmodel.StatsIntervalHourly:
		return model.IntervalHourly
	case gqlmodel.StatsIntervalDaily:
		return model.IntervalDaily
	case gqlmodel.StatsIntervalWeekly:
		return model.IntervalWeekly
	case gqlmodel.StatsIntervalMonthly:
		return model.IntervalMonthly
	case gqlmodel.StatsIntervalYearly:
		return model.IntervalYearly
	case gqlmodel.StatsIntervalSingle:
		return model.IntervalSingle
	default:
		panic("unknown interval type " + interval)
	}
}

// ExternalInterval converts interval.
func ExternalInterval(interval model.Interval) gqlmodel.StatsInterval {
	switch interval {
	case model.IntervalHourly:
		return gqlmodel.StatsIntervalHourly
	case model.IntervalDaily:
		return gqlmodel.StatsIntervalDaily
	case model.IntervalWeekly:
		return gqlmodel.StatsIntervalWeekly
	case model.IntervalMonthly:
		return gqlmodel.StatsIntervalMonthly
	case model.IntervalYearly:
		return gqlmodel.StatsIntervalYearly
	case model.IntervalSingle:
		return gqlmodel.StatsIntervalSingle
	default:
		panic("unknown interval type " + interval)
	}
}
