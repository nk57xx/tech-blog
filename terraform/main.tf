
terraform {
  required_version = ">= 0.13.0"
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "nk57xx"

    workspaces {
      name = "tech-blog"
    }
  }
}

# Variables
variable "bucket_name" {
  type    = string
  default = "norberts.tech-blog.cloudtalents"
}



# Provider

provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

# S3 Bucket for static website

resource "aws_s3_bucket" "static-website" {
  bucket = var.bucket_name

  tags = {
    Name = "Norberts tech-blog"
  }
}

resource "aws_s3_bucket_policy" "static-website" {
  bucket = aws_s3_bucket.static-website.id
  policy = data.aws_iam_policy_document.static-website.json
}

data "aws_iam_policy_document" "static-website" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = [
      "${aws_s3_bucket.static-website.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values = [
        "${aws_cloudfront_distribution.static-website.arn}"
      ]
    }
  }
}

# CloudFront

resource "aws_cloudfront_origin_access_control" "static-website" {
  name                              = aws_s3_bucket.static-website.id
  origin_access_control_origin_type = "OAC for S3 bucket ${aws_s3_bucket.static-website.id}"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "static-website" {
  depends_on = [
    aws_s3_bucket.static-website
  ]

  origin {
    domain_name              = aws_s3_bucket.static-website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static-website.id
    origin_id                = "static-website"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD"
    ]
    cached_methods = [
      "GET",
      "HEAD"
    ]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    target_origin_id       = "static-website"
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Outputs

output "s3_bucket" {
  value = aws_s3_bucket.static-website.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.static-website.domain_name
}

output "cloudfront_id" {
  value = aws_cloudfront_distribution.static-website.id
}


