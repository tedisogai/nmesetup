// ============================================================
// modules/compute-gallery.bicep
// Azure Compute Gallery (旧 Shared Image Gallery)
// Nerdio Manager がゴールデンイメージを管理・配布するために使用
// ============================================================

targetScope = 'resourceGroup'

// ── Parameters ───────────────────────────────────────────────
param location string
param tags object

@description('Azure Compute Gallery name (letters, numbers, periods, underscores only)')
param galleryName string

@description('Gallery description')
param galleryDescription string = 'Azure Compute Gallery for Nerdio Manager for Enterprise'

// ── Azure Compute Gallery ──────────────────────────────────────
resource gallery 'Microsoft.Compute/galleries@2023-07-03' = {
  name: galleryName
  location: location
  tags: tags
  properties: {
    description: galleryDescription
  }
}

// ── Outputs ───────────────────────────────────────────────────
output galleryId string = gallery.id
output galleryName string = gallery.name
