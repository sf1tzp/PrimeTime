import Foundation

package extension Notification.Name {
    /// Posted on the *distributed* notification center by any process that
    /// writes the store from outside the app — today the moment-tally CLI's
    /// timer commands (#80). The app has no cross-process store observation
    /// (no GRDB ValueObservation), so this is how a running app learns that
    /// `moment-tally start`/`stop` changed the data under it.
    static let momentTallyStoreDidChange =
        Notification.Name("com.streetfortress.MomentTally.storeDidChange")
}
