# Rx wrapper for AWSMobileClient

Possible implementation for Rx driven projects

# Wrapped features
<ul>
    <li>Configuration is consumed via obsevable of a listener;</li>
    <li>Username/password login;</li>
    <li>Social login(currently for Apple and Facebook);</li>
    <li>Logout;</li>
    <li>Relogin for username/password flow;</li>
</ul>

# Notes

<ul>
    <li>A configuration consumption and the login action can be executed in async manner;</li>
    <li>Login and a private part request must be synchronized;</li>
    <li>A token obtained via a social provider is managed within the wrapper, because it's expiration time isn't managed inside AWSMobileClient;</li>
</ul>

# High-level usage
![Diagram](/readme-resources/diagram.png "Highlevel usage")