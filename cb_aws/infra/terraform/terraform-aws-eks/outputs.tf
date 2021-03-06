output "endpoint" {
  value = aws_eks_cluster.eksCluster.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.eksCluster.certificate_authority[0].data
}
