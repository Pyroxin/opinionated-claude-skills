# Java Programmer Skill Assets

This directory contains configuration files referenced by the java-programmer skill.

## Configuration Files

### checkstyle.xml
Checkstyle configuration for enforcing Java coding standards.

Reference in Maven:
```xml
<configuration>
    <configLocation>checkstyle.xml</configLocation>
</configuration>
```

Reference in Gradle:
```groovy
checkstyle {
    configFile = file("${rootDir}/checkstyle.xml")
}
```

### spotbugs-exclude.xml (optional)
SpotBugs exclusion filter for false positives.

Reference in Maven:
```xml
<configuration>
    <excludeFilterFile>spotbugs-exclude.xml</excludeFilterFile>
</configuration>
```

## Adding Configuration Files

You can add your own checkstyle.xml and other configuration files here. The skill references these as examples that can be customized for your projects.

Example structure:
```
assets/
├── README.md (this file)
├── checkstyle.xml (to be added)
├── spotbugs-exclude.xml (optional)
└── pmd-ruleset.xml (optional)
```

## Usage in Projects

Copy these configuration files to your project root and reference them in your pom.xml or build.gradle as shown above.
