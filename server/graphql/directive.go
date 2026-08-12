package graphql

import (
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlschema"
)

// NewDirective creates a new directive.
func NewDirective() gqlschema.DirectiveRoot {
	return gqlschema.DirectiveRoot{
		HasRole: auth.HasRole(),
	}
}
