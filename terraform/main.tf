
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

variable "blog_domain" {
  type    = string
  default = "norbert.cloudtalents.io"
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
  description                       = "OAC for S3 bucket ${aws_s3_bucket.static-website.id}"
  origin_access_control_origin_type = "s3"
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

  aliases = ["norbert.cloudtalents.io"]

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

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.index.arn
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
    acm_certificate_arn      = aws_acm_certificate.my_certificate.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
    #cloudfront_default_certificate = true
  }

  custom_error_response {
    error_caching_min_ttl = 86400
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
  }

  custom_error_response {
    error_caching_min_ttl = 86400
    error_code            = 403
    response_code         = 403
    response_page_path    = "/404.html"
  }

  custom_error_response {
    error_caching_min_ttl = 86400
    error_code            = 500
    response_code         = 500
    response_page_path    = "/404.html"
  }
}

resource "aws_cloudfront_function" "index" {
  name    = "index"
  runtime = "cloudfront-js-2.0"
  comment = "Add index.html to request URLs without a file name"
  publish = true
  code    = file("function.js")
}

# ACM

resource "aws_acm_certificate" "my_certificate" {
  provider          = aws.us-east-1
  domain_name       = var.blog_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# IAM

# Get current AWS Account ID
data "aws_caller_identity" "current" {}

# Import GitHub Action Role
data "aws_iam_role" "github_actions" {
  name = "GitHubActions-tech-blog"
}

# Update existing Policy for GitHubActions-tech-blog Role and Policy
resource "aws_iam_role_policy" "github_actions" {
  name = "GitHubActions-tech-blog"
  role = data.aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Sid" : "GitHubActionsPolicy",
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        "Resource" : [
          "${aws_s3_bucket.static-website.arn}/*",
          "${aws_s3_bucket.static-website.arn}"
        ]
      },
      {
        "Sid" : "CloudFrontInvalidateRequests",
        "Effect" : "Allow",
        "Action" : "cloudfront:CreateInvalidation",
        "Resource" : "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.static-website.id}"
      }
    ]
  })
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


