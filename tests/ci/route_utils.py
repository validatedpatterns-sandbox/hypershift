from ocp_resources.route import Route


def _route_url(openshift_dyn_client, namespace, name):
    routes = [
        route
        for route in Route.get(
            dyn_client=openshift_dyn_client, namespace=namespace, name=name
        )
    ]

    assert (
        len(routes) == 1
    ), f"Expected to find the route '{name}' in the namespace '{namespace}'"

    spec = routes[0].instance.spec
    scheme = "https" if getattr(spec, "tls", None) else "http"
    return f"{scheme}://{spec.host}"
