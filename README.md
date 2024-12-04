# Hosted Control Planes ( HyperShift )

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

[Live build status](https://validatedpatterns.io/ci/?pattern=mcgitops)

## Start Here

This pattern use the validated patterns gitops framework to deploy and configure the multicluster-engine operator with the hypershift (hosted control planes) feature. You can deploy the AWS S3 Controller for kubernetes to create the s3 bucket necessary for HCP and OIDC - you can also choose not too. Everything is in place so that you can be completely contained within this pattern. If you choose to create the s3 bucket on your own, it will need to have a public policy attached to it. Again this pattern will create the bucket, policy and associate the policy with the bucket. 

We also provide a means to configure oAuth to your cluster. The currently deployed provider is GitHub, and in a future release we'll have htpasswd and maybe something fun like doppler. 

## PreRequisites

### HyperShift

1. A freshly installed cluster. Either a SNO, 3-Node, or other supported variant of an OpenShift Cluster deployment. 

**NOTE** The cluster we use internally is a 3-Node, m5.4xlarge cluster and that has been plenty

2. You will need to complete the `values-secret.yaml.template` file and configure the paths for your secrets; the default is `(~/.aws/credentials)`

3. STS credentials are also required now for cluster provisioning and deprovisioning. Please see: [HyperShift Automation Repo](https://github.com/validatedpatterns/hypershift-automation.git) for further automation.

4. Finally, edit `values-hypershift.yaml` if you want the automation to configure a scoped clusterrole and clusterrolebinding that allows users to provision/deprovison hypershift clusters but not really anything else.

### ACK S3 Controller

1. For both hypershift and aws s3 controller we need to configure secrets that use your aws credentials. The default uses
`~/.aws/credentials` for parsing the credential.

2. If you elect to not use ACK for creating your s3 bucket, please see the **NOTE** below. Some extra configuration is
necessary to ensure you don't deploy extra operators and configurations you don't need.

### oAuth Provider

1. Update `values-global.yaml` by uncommenting out the oauth section. Provide the necessary informatino for configuring oauth with a github provider.

2. Create a file in your `$HOME` directory called `.oauth` ex: `~/.oauth` - copy/paste the secret GitHub provided into that file and save/close.

3. Update your values-secret.yaml.template file with the correct path 

## Actions

To get started you will need to fork & clone this repository:

- `git clone https://github.com/validatedpatterns-sandbox/hypershift`

- `cd hypershift`

- `vim values-hypershift.yaml`

- `git commit & push your changes`

- `run ./patterns.sh make install`

|Parameter | Default (if defined) | Purpose |
|----------|----------------------|---------|
|useExternalSecrets| true | When using the patterns framework this should be true. This will provision the necessary secrets for you using eso|
| createBucket | true | This provisions the s3 bucket to be used by hypershift |
| region | `<n/a>` | Define the region that you want your s3 bucket created in |
| bucketName | `<n/a>` | Define the name of your bucket - must be DNS compatible (no `_'s` or special characters) |
| additionalTags | `<n/a>` | Create a map of tags to be added to the bucket in `key: value` format|

An example `values-hypershift.yaml` that has been completed:

```yaml
global:
  useExternalSecrets: true
  s3:
    createBucket: true
    region: us-west-1
    bucketName: jrickard-hcp
    additionalTags:
      bucketOwner: jrickard
      lifecycle: keep

```

**NOTE**
If you set `createBucket` to `false` you will also need to edit `values-hub.yaml` and either comment or remove references to ack-system / s3 in the following locations:

```yaml
namespaces:
    - ack-system

subscriptions:
  s3:
    name: ack-s3-controller
    namespace: ack-system
    channel: alpha
    source: community-operators

projects:
  - s3

applications:
  s3:
    name: s3-controller
    namespace: ack-system
    project: s3
    path: charts/all/ack-s3

```

If you've followed a link to this repository, but are not really sure what it contains
or how to use it, head over to [HyperShift ValidatedPatterns](http://validatedpatterns.io/hypershift)
for additional context and installation instructions
