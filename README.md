# Hosted Control Planes ( HyperShift )

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

[Live build status](https://validatedpatterns.io/ci/?pattern=mcgitops)

## Start Here

This pattern deploys and configures the multicluster-engine operator with the hypershift (hosted control planes) feature.

Within the pattern are some optional deployment configurations that can assist with your HyperShift deployment as well as some Day2 configurations.

- AWS S3 Controller for Kubernetes (ack-s3)

  - Configuring this will create a bucket, a public bucket policy and associate the two resources together.

- oAuth Provider

  - GitHub is the default provider, but others (GitLab, Google, htpasswd) could be configured.

- RBAC

  - A cluster role and cluster role binding are created for a provided list of users. This role will grant the user the ability to create/destroy/view the resources required for creating hostedclusters on HyperShift.

## PreRequisites

### HyperShift

- A freshly installed cluster. Either a SNO, 3-Node, or other supported variant of an OpenShift Cluster deployment.

**[NOTE]**
>
> The cluster we use internally is a 3-Node, m5.4xlarge cluster and that has been plenty
>

- Update the  `values-secret.yaml.template` template with any changes to the paths for your secrets; the default is `(~/.aws/credentials)`

- STS credentials are also required now for cluster provisioning and deprovisioning. Please see: [HyperShift Automation Repository](https://github.com/validatedpatterns/hypershift-automation.git) for further automation.

- Finally, edit `values-hypershift.yaml`
  
  - Provide the region where the s3 bucket resides

  - Provide the bucket name to be used for the OIDC state

**[NOTE]**
>
> If you use the ack-s3 controller option to deploy your bucket, set `createBucket` to `true` in `values-hypershift.yaml`
>

### ACK S3 Controller

- Enable this feature:

  - Edit `values-global.yaml`

    - Set `.main.clusterGroupName` to `prod`

  - Edit `values-hypershift.yaml`

    - Provide the region to create the bucket in

    - Provide the bucket name

    - set `.global.s3.createBucket` to `true`

- For both hypershift and aws s3 controller we need to configure secrets that use your aws credentials. The default uses `~/.aws/credentials` for parsing the credential.

### oAuth Provider

- Enable this feature:

  - Edit `values-global.yaml`

    - Set `.main.clusterGroupName` to `prod`

  - Edit `values-hypershift.yaml`

    - Set `.global.oauth.github.clientID`

    - Set `.global.oauth.github.orgs.name`

  - Edit `values-secret-hypershift.yaml.template` or `~/values-secret-hypershift.yaml`

    - Uncomment the following block:

    ```yaml
    - name: oauthCreds
      fields:
      - name: content
        path: ~/.oauth
    ```

**[IMPORTANT]**
>
> Using the client secret from GitHub oAuth tool, create a local file `~/.oauth` wtih the github client secret
>

## Actions

To get started you will need to fork & clone this repository:

- `git clone https://github.com/validatedpatterns-sandbox/hypershift`

- `cd hypershift`

- `cp values-hypershift.yaml.template $HOME/values-secret-hypershift.yaml`

- `git commit & push your changes`

- `run ./patterns.sh make install`

## Examples

### Example values-hypershift.yaml

```yaml
global:
  hypershift:
    oidc:
      region: us-west-2
      bucketName: hcpoidc

  s3:
    # Should the pattern create the s3 bucket(true), or bring your own (false).
    createBucket: true

    # Any additional tags to add to a bucket created by the pattern
    additionalTags:
      lifecycle: keep

  oauth:
    type: GitHub
    secretName: ocp-github-oauth
    github:
      clientID: a1b2c3f4d5g6h7i8j9k0
      orgs:
      - name: validatedpatterns

rbac:
  create: true
  users:
    - user1
    - user2
    - user3

  ```

#### Example $HOME/.oauth

```sh
cat ~/.oauth
```

```sh
a1b2c3f4d5g6h7i8j9k0a1b2c3f4d5g6h7i8j9k0
```

If you've followed a link to this repository, but are not really sure what it contains
or how to use it, head over to [HyperShift ValidatedPatterns](http://validatedpatterns.io/hypershift)
for additional context and installation instructions
