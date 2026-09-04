use std::time::Duration;

use anyhow::{Context, Result};
use rusty_s3::actions::{CreateBucket, GetObject, HeadObject, PutObject, S3Action};
use rusty_s3::{Bucket, Credentials, UrlStyle};
use url::Url;

/// S3-compatible object storage. MinIO locally, real S3 in production — the
/// only difference is the endpoint and `UrlStyle`.
#[derive(Clone)]
pub struct Storage {
    bucket: Bucket,
    creds: Credentials,
}

impl Storage {
    /// How long a presigned URL stays valid. Long enough to upload a photo on a
    /// bad connection, short enough that a URL leaking from a log or a shared
    /// screenshot is not a durable write capability.
    pub const UPLOAD_TTL: Duration = Duration::from_secs(15 * 60);
    pub const DOWNLOAD_TTL: Duration = Duration::from_secs(60 * 60);

    pub fn from_env() -> Result<Self> {
        let endpoint: Url = std::env::var("S3_ENDPOINT")
            .context("S3_ENDPOINT must be set")?
            .parse()
            .context("S3_ENDPOINT is not a valid URL")?;
        let name = std::env::var("S3_BUCKET").context("S3_BUCKET must be set")?;
        let region = std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".into());

        // Path style is required for MinIO: virtual-host style would need
        // wildcard DNS for `<bucket>.localhost`, which does not resolve.
        let bucket = Bucket::new(endpoint, UrlStyle::Path, name, region)
            .context("could not construct S3 bucket handle")?;

        let creds = Credentials::new(
            std::env::var("S3_ACCESS_KEY").context("S3_ACCESS_KEY must be set")?,
            std::env::var("S3_SECRET_KEY").context("S3_SECRET_KEY must be set")?,
        );

        Ok(Self { bucket, creds })
    }

    /// Create the bucket if it isn't there. Idempotent: an existing bucket
    /// reports 409, which is success for our purposes.
    pub async fn ensure_bucket(&self, http: &reqwest::Client) -> Result<()> {
        let url = CreateBucket::new(&self.bucket, &self.creds).sign(Duration::from_secs(60));
        let response = http.put(url).send().await?;
        match response.status().as_u16() {
            200 | 204 | 409 => Ok(()),
            other => {
                let body = response.text().await.unwrap_or_default();
                // BucketAlreadyOwnedByYou is also a success.
                if body.contains("BucketAlreadyOwnedByYou") || body.contains("BucketAlreadyExists") {
                    Ok(())
                } else {
                    anyhow::bail!("could not create bucket (status {other}): {body}")
                }
            }
        }
    }

    /// A URL the client can PUT the photo to directly.
    ///
    /// This is the reason media-svc exists as its own service: bytes go straight
    /// from phone to object storage, so neither API process ever buffers a
    /// multi-megabyte upload.
    pub fn presign_put(&self, key: &str, content_type: &str) -> Url {
        let mut action = PutObject::new(&self.bucket, Some(&self.creds), key);
        action.headers_mut().insert("content-type", content_type.to_string());
        action.sign(Self::UPLOAD_TTL)
    }

    pub fn presign_get(&self, key: &str) -> Url {
        GetObject::new(&self.bucket, Some(&self.creds), key).sign(Self::DOWNLOAD_TTL)
    }

    /// What the object store actually holds: `(content_type, byte_size)`.
    ///
    /// A presigned URL is not a trust boundary. The client chose what to PUT, so
    /// what it *claimed* when requesting the URL proves nothing — this is the
    /// only trustworthy source for type and size.
    pub async fn head(&self, http: &reqwest::Client, key: &str) -> Result<Option<(String, i64)>> {
        let url = HeadObject::new(&self.bucket, Some(&self.creds), key).sign(Duration::from_secs(60));
        let response = http.head(url).send().await?;
        if !response.status().is_success() {
            return Ok(None);
        }
        let content_type = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("application/octet-stream")
            .to_string();
        let size = response
            .headers()
            .get(reqwest::header::CONTENT_LENGTH)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(0);
        Ok(Some((content_type, size)))
    }

    pub async fn get_bytes(&self, http: &reqwest::Client, key: &str) -> Result<Vec<u8>> {
        let response = http.get(self.presign_get(key)).send().await?.error_for_status()?;
        Ok(response.bytes().await?.to_vec())
    }

    pub async fn put_bytes(
        &self,
        http: &reqwest::Client,
        key: &str,
        content_type: &str,
        bytes: Vec<u8>,
    ) -> Result<()> {
        http.put(self.presign_put(key, content_type))
            .header("content-type", content_type)
            .body(bytes)
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }
}
