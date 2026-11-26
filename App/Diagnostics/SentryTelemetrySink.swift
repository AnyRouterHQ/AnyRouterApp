import Sentry

/// The only file that talks to the Sentry SDK. Created only when a DSN is set.
struct SentryTelemetrySink: TelemetrySink {
    /// Privacy settings: no PII, no IP, no screenshots, no network or UI breadcrumbs, no performance traces,
    /// no sessions. Breadcrumbs are scrubbed of URL query strings. Every event passes `shareEnabled` first.
    static func start(dsn: String, shareEnabled: @escaping @Sendable () -> Bool) {
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableAutoBreadcrumbTracking = false
            options.enableUserInteractionTracing = false
            options.enableAutoSessionTracking = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.tracesSampleRate = 0
            options.beforeBreadcrumb = { crumb in
                crumb.message = crumb.message.map { BreadcrumbScrubber.scrub($0) }
                crumb.data = BreadcrumbScrubber.scrub(data: crumb.data)
                return crumb
            }
            options.beforeSend = { event in shareEnabled() ? event : nil }
        }
    }

    func record(_ event: TelemetryEvent) {
        let crumb = Breadcrumb(level: .info, category: event.category.rawValue)
        crumb.message = event.name
        crumb.data = event.properties
        SentrySDK.addBreadcrumb(crumb)
    }
}
