import Foundation
#if os(tvOS)
import TVServices
#endif

func notifyTopShelfContentChanged() {
    #if os(tvOS)
    TVTopShelfContentProvider.topShelfContentDidChange()
    #endif
}
