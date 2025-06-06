output "ec2_public_ip" {
  description = "앱 서버 EC2 퍼블릭 IP"
  value       = aws_instance.app_server.public_ip
}

output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value       = aws_db_instance.app_db.address
}

