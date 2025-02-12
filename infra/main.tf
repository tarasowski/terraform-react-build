provider "aws" {
  region = var.aws_region
}

resource "random_integer" "static_number" {
  min = 1000
  max = 9999

  keepers = {
    always_same = "static_value"
  }
}

resource "aws_s3_bucket" "site" {
  bucket = "${var.site_domain}-${random_integer.static_number.result}"
}


resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "site" {
  bucket = aws_s3_bucket.site.id

  acl = "public-read"
  depends_on = [
    aws_s3_bucket_ownership_controls.site,
    aws_s3_bucket_public_access_block.site
  ]
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*",
        ]
      },
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.site
  ]
}



# Warte darauf, dass der Build abgeschlossen ist
data "external" "build_frontend" {
  program = ["bash", "-c", <<EOT
    cd ../app
    npm install > /dev/null 
    npm run build > /dev/null
    echo '{ "status": "completed" }'
  EOT
  ]
}

# Upload files to the S3 bucket
resource "aws_s3_object" "source_files" {
  bucket = aws_s3_bucket.site.id

  for_each = fileset("${path.module}/../app/dist", "**/*")

  key    = each.value
  source = "${path.module}/../app/dist/${each.value}"
  content_type = lookup({
    ".js"   = "application/javascript"
    ".css"  = "text/css"
    ".html" = "text/html"
  }, regex("\\.[^.]+$", each.value), "binary/octet-stream")

  depends_on = [
    data.external.build_frontend
  ]
}

