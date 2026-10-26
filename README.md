# Food_Connect

# Food_Connect --- Project Overview and Technical Plan

**Document type:** Project requirements and technology plan\
**Project name:** FoodConnect\
**Status:** Initial project plan\
**Purpose:** Describe what we intend to build, how it will work, and
which technologies we plan to use.

------------------------------------------------------------------------

## 1. Project Overview

FoodConnect is a web application that connects restaurants, hotels,
caterers, and event organizers that have surplus food with nearby
verified non-governmental organizations (NGOs) that can collect and
distribute it.

The platform focuses on one simple workflow:

1.  A food donor posts a donation request.
2.  FoodConnect finds all active, verified NGOs located within a **5 km
    radius** of the pickup location.
3.  All matching NGOs receive a notification.
4.  The first NGO to successfully accept the donation gets it.
5.  The restaurant receives a notification naming the NGO that accepted
    the donation.
6.  The NGO contacts the restaurant and independently arranges pickup.
7.  The donor and NGO confirm the handover through FoodConnect.

**FoodConnect coordinates donations; it does not manage transportation.**
There will be no driver assignment, volunteer dispatch, route planning,
or live delivery tracking in the initial version.

## 2. Problem We Are Solving

Restaurants, hotels, caterers, and event organizers can have edible
surplus food that is available for a limited time. Nearby NGOs may be
able to collect and distribute that food, but donors and NGOs may not
know how to find each other quickly.

FoodConnect provides a central place to publish surplus food and
automatically notify nearby NGOs. This can reduce the effort required to
find a recipient and make local food donation coordination faster and
more organized.

## 3. Project Goals

-   Make it easy for a donor to post a surplus-food donation request.
-   Automatically identify verified, active NGOs within 5 km of the
    donation pickup location.
-   Notify all matching NGOs when a new eligible donation is posted.
-   Ensure that only one NGO can successfully claim a donation.
-   Notify the restaurant as soon as an NGO successfully claims the
    donation.
-   Let the NGO arrange pickup directly with the restaurant.
-   Record whether the food was collected and whether the handover was
    confirmed.
-   Provide administrators with tools to verify organizations and
    monitor platform activity.
-   Maintain reliable records of donations, claims, notifications,
    cancellations, and handovers.
-   Provide basic statistics about donation activity and food
    successfully redistributed.
