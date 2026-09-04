pub mod auth;
pub mod cache;
pub mod config;
pub mod routes;
pub mod state;

use axum::Router;
use state::AppState;

/// Build the full router.
///
/// Separate from `main` so integration tests can mount the real application
/// against a test database instead of re-declaring routes and drifting from it.
pub fn app(state: AppState) -> Router {
    Router::new()
        .merge(routes::health::routes())
        .merge(auth::routes())
        .merge(routes::catches::routes())
        .merge(routes::friends::routes())
        .layer(tower_http::trace::TraceLayer::new_for_http())
        // Bodies here are small JSON documents; photos go straight to object
        // storage via media-svc and never traverse this service.
        .layer(tower_http::limit::RequestBodyLimitLayer::new(64 * 1024))
        .with_state(state)
}
