import pytest
from validatedpatterns_tests.interop import components, subscription


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_subscription_status_standalone(openshift_dyn_client):
    expected_subs = {
        "openshift-gitops-operator": ["openshift-gitops-operator"],
        "multicluster-engine": ["multicluster-engine"],
        "openshift-external-secrets-operator": ["external-secrets-operator"],
    }
    subscription.assert_subscription_status(openshift_dyn_client, expected_subs)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_site_reachable_hub(openshift_dyn_client):
    components.assert_site_reachable(openshift_dyn_client)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_argocd_reachable_standalone(openshift_dyn_client):
    components.assert_argocd_reachable(openshift_dyn_client)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_pod_status_standalone(openshift_dyn_client):
    projects = [
        "patterns-operator",
        "vp-gitops",
        "vault",
        "external-secrets-operator",
        "hypershift",
        "multicluster-engine",
    ]
    components.assert_pod_status(openshift_dyn_client, projects, skip_check=[])
