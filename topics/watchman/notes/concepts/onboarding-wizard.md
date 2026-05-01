---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [watchman, onboarding, byod, wireguard, ux, f-001]
---

# Onboarding Wizard

[[watchman/_summary|Actuate Watchman]]'s onboarding wizard (feature F-001) is a 9-step self-service flow that takes a customer from unboxing hardware to live monitoring in under 10 minutes. This BYOD (Bring Your Own Device) approach is central to [[watchman-repo|Watchman]]'s go-to-market strategy -- targeting small businesses with 4-30 existing cameras that can be connected without professional installation.

## The 10-Minute Target

Onboarding time < 10 minutes is one of [[watchman-repo|Watchman]]'s three headline KPIs. The wizard is designed to eliminate the need for a technician visit, which is a major cost and friction point in traditional surveillance deployments. Every step is guided and sequential, reducing cognitive load for non-technical operators.

## The 9 Steps

### Step 1: Deployment Type Selection
The operator chooses their connectivity method. Options include the Teltonika RUT241 router (hardware appliance) or the Actuate Secure App (software-only). This determines the setup flow for subsequent steps.

### Step 2: WireGuard Tunnel Setup
Establishes the encrypted VPN tunnel between the customer's network and Actuate's cloud. [[WireGuard]] was chosen for its simplicity and performance. The [[multi-agent-architecture|Connectivity Agent]] manages this tunnel throughout the system's lifetime.

### Step 3: WiFi Configuration
Configures the router or app's network connection to the customer's local network. This step ensures the device can reach both the cameras (on the local network) and Actuate's cloud (via the internet).

### Step 4: Camera Discovery
Automatic discovery of cameras on the local network using ONVIF and [[rtsp-deep-dive|RTSP]] protocols. The system scans for compatible devices and presents them to the operator. This is where BYOD becomes concrete -- the customer's existing cameras are detected without manual IP configuration.

### Step 5: Site Type Classification
The operator classifies their site (retail store, warehouse, office, parking lot, etc.). This feeds into the [[multi-agent-architecture|Site Context Agent]], which uses the classification to initialise its baseline activity model and set appropriate default thresholds.

### Step 6: Camera Selection + Naming/Zone Assignment
The operator selects which discovered cameras to monitor, gives them human-readable names (e.g. "Front Door", "Loading Dock"), and assigns them to zones. Zone assignment is important for the [[multi-agent-architecture|Assessment Agent's]] cross-camera correlation -- it needs to know spatial relationships.

### Step 7: Emergency Contacts
Configure up to 5 emergency contacts for the [[multi-agent-architecture|Escalation Agent's]] notification chains. Each contact can be assigned to different escalation tiers (CRITICAL, HIGH, MEDIUM) with their preferred notification methods (push, SMS, phone call).

### Step 8: Protection Priorities
The operator specifies what matters most at their site -- perimeter intrusion, after-hours access, fire detection, etc. These priorities influence the [[patrol-vs-active-modes|Patrol Agent's]] camera prioritisation during sweeps and the Assessment Agent's severity weighting. A retail store might prioritise shoplifting and after-hours intrusion; a warehouse might prioritise fire and perimeter breach.

### Step 9: Go Live
An animated deployment sequence plays while the system initialises all agents, starts the first patrol cycle, and confirms connectivity to every selected camera. This is a UX flourish designed to create a sense of event -- the moment the site goes from passive to protected.

## Design Rationale

The wizard's sequencing is deliberate: infrastructure first (steps 1-3), discovery (step 4), context (steps 5-6), people (step 7), policy (step 8), activation (step 9). Each step provides input that downstream agents need before they can operate. The strict ordering means the system is fully configured by the time Go Live fires -- no post-setup configuration required for basic operation.
