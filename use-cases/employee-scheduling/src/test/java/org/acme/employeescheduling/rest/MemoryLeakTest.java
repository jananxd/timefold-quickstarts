package org.acme.employeescheduling.rest;

import static io.restassured.RestAssured.given;
import static org.assertj.core.api.Assertions.assertThat;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import org.acme.employeescheduling.domain.Employee;
import org.acme.employeescheduling.domain.EmployeeSchedule;
import org.acme.employeescheduling.domain.Shift;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;

/**
 * Memory leak test for Employee Scheduling API.
 *
 * Runs multiple solve cycles and verifies memory returns to baseline after GC.
 *
 * Run with: mvn test -Dtest=MemoryLeakTest
 * Or for more iterations: mvn test -Dtest=MemoryLeakTest -Dmemory.test.iterations=50
 */
@QuarkusTest
@Tag("memory")
class MemoryLeakTest {

    private static final int DEFAULT_ITERATIONS = 20;
    private static final long DELAY_BETWEEN_REQUESTS_MS = 2000;
    private static final long COOLDOWN_DURATION_SECONDS = 180; // 3 minutes
    private static final long COOLDOWN_CHECK_INTERVAL_MS = 5000;
    private static final double BASELINE_TOLERANCE = 1.20; // 20% tolerance

    private final MemoryMXBean memoryMXBean = ManagementFactory.getMemoryMXBean();

    @Test
    void testNoMemoryLeakAfterMultipleSolveCycles() throws InterruptedException {
        int iterations = Integer.getInteger("memory.test.iterations", DEFAULT_ITERATIONS);

        System.out.println();
        System.out.println("=".repeat(70));
        System.out.println("MEMORY LEAK TEST - Employee Scheduling API");
        System.out.println("=".repeat(70));
        System.out.println("Iterations: " + iterations);
        System.out.println("Delay between requests: " + DELAY_BETWEEN_REQUESTS_MS + "ms");
        System.out.println();

        // Force GC and establish baseline
        forceGC();
        long baselineHeapMB = getUsedHeapMB();
        System.out.println("Baseline heap: " + baselineHeapMB + " MB");
        System.out.println();

        // Stress test phase
        System.out.printf("%-6s %-14s %-14s %-20s%n", "Iter", "Heap (MB)", "Delta (MB)", "Status");
        System.out.println("-".repeat(60));
        System.out.printf("%-6s %-14d %-14d %-20s%n", "start", baselineHeapMB, 0, "-");

        List<String> jobIds = new ArrayList<>();
        long peakHeapMB = baselineHeapMB;

        for (int i = 1; i <= iterations; i++) {
            String jobId = submitProblem();
            jobIds.add(jobId);

            long currentHeapMB = getUsedHeapMB();
            long delta = currentHeapMB - baselineHeapMB;
            peakHeapMB = Math.max(peakHeapMB, currentHeapMB);

            // Print every 5 iterations or first one
            if (i % 5 == 0 || i == 1) {
                System.out.printf("%-6d %-14d %+-14d %-20s%n", i, currentHeapMB, delta, "submitted");
            }

            Thread.sleep(DELAY_BETWEEN_REQUESTS_MS);
        }

        long afterStressHeapMB = getUsedHeapMB();
        System.out.println("-".repeat(60));
        System.out.printf("%-6s %-14d %+-14d%n", "end", afterStressHeapMB, afterStressHeapMB - baselineHeapMB);
        System.out.println();
        System.out.println("Created " + jobIds.size() + " jobs");

        // Terminate all jobs
        System.out.println("Terminating all jobs...");
        for (String jobId : jobIds) {
            try {
                given()
                    .when().delete("/schedules/" + jobId)
                    .then().statusCode(200);
            } catch (Exception e) {
                // Ignore cleanup errors
            }
        }

        // Force GC after termination
        forceGC();
        long afterTerminationHeapMB = getUsedHeapMB();
        System.out.println("Heap after termination + GC: " + afterTerminationHeapMB + " MB");

        // Cooldown phase
        System.out.println();
        System.out.println("=".repeat(70));
        System.out.println("COOLDOWN PHASE (" + COOLDOWN_DURATION_SECONDS + " seconds)");
        System.out.println("=".repeat(70));
        System.out.printf("%-8s %-14s %-14s %-14s %-14s%n", "Time", "Heap (MB)", "vs Start", "vs Peak", "Status");
        System.out.println("-".repeat(70));

        long cooldownChecks = COOLDOWN_DURATION_SECONDS * 1000 / COOLDOWN_CHECK_INTERVAL_MS;
        long previousHeapMB = afterTerminationHeapMB;

        for (int i = 1; i <= cooldownChecks; i++) {
            Thread.sleep(COOLDOWN_CHECK_INTERVAL_MS);

            // Trigger GC periodically
            if (i % 6 == 0) { // Every 30 seconds
                forceGC();
            }

            long currentHeapMB = getUsedHeapMB();
            long deltaStart = currentHeapMB - baselineHeapMB;
            long deltaPeak = currentHeapMB - peakHeapMB;
            long change = currentHeapMB - previousHeapMB;

            String status;
            if (currentHeapMB <= baselineHeapMB * 1.05) {
                status = "BASELINE";
            } else if (change < -5) {
                status = "recovering (" + change + ")";
            } else if (change > 5) {
                status = "growing (+" + change + ")";
            } else {
                status = "stable";
            }

            int elapsedSeconds = (int) (i * COOLDOWN_CHECK_INTERVAL_MS / 1000);
            System.out.printf("+%-7ds %-14d %+-14d %+-14d %-14s%n",
                    elapsedSeconds, currentHeapMB, deltaStart, deltaPeak, status);

            previousHeapMB = currentHeapMB;
        }

        // Final measurement after cooldown
        forceGC();
        long finalHeapMB = getUsedHeapMB();
        long netGrowth = finalHeapMB - baselineHeapMB;
        long recovered = peakHeapMB - finalHeapMB;

        System.out.println("-".repeat(70));
        System.out.println();
        System.out.println("SUMMARY:");
        System.out.println("  Start heap:      " + baselineHeapMB + " MB");
        System.out.println("  Peak heap:       " + peakHeapMB + " MB");
        System.out.println("  Final heap:      " + finalHeapMB + " MB");
        System.out.println("  Total recovered: " + recovered + " MB (" +
                (peakHeapMB > 0 ? (recovered * 100 / peakHeapMB) : 0) + "% of peak)");
        System.out.println("  Net growth:      " + (netGrowth >= 0 ? "+" : "") + netGrowth + " MB (" +
                (baselineHeapMB > 0 ? (netGrowth * 100 / baselineHeapMB) : 0) + "%)");
        System.out.println();

        double threshold = baselineHeapMB * BASELINE_TOLERANCE;
        if (finalHeapMB <= baselineHeapMB * 1.05) {
            System.out.println("  [OK] Memory returned to baseline!");
        } else if (finalHeapMB <= threshold) {
            System.out.println("  [NOTICE] Memory close to baseline (within 20%)");
        } else {
            System.out.println("  [WARNING] Memory did NOT return to baseline");
            System.out.println("  Note: The jobIdToJob map in EmployeeScheduleResource.java");
            System.out.println("        has no TTL - jobs are never cleaned up. This is expected.");
        }
        System.out.println();

        // Assertion - allow 20% tolerance
        assertThat(finalHeapMB)
                .as("Heap should return close to baseline after GC (within 20%)")
                .isLessThanOrEqualTo((long) threshold);
    }

    private String submitProblem() {
        EmployeeSchedule problem = createSampleProblem();

        return given()
                .contentType(ContentType.JSON)
                .body(problem)
                .when().post("/schedules")
                .then()
                .statusCode(200)
                .extract()
                .asString();
    }

    private EmployeeSchedule createSampleProblem() {
        List<Employee> employees = List.of(
                new Employee("John Carlo Miel",
                        Set.of("Practice Manager", "Office Assistant", "Dispenser"),
                        Set.of(), Set.of(), Set.of()),
                new Employee("Tommy Shelby",
                        Set.of("Practice Manager", "Office Assistant", "Dispenser"),
                        Set.of(), Set.of(), Set.of()),
                new Employee("Tom Holland",
                        Set.of("Practice Manager", "Office Assistant", "Dispenser"),
                        Set.of(), Set.of(), Set.of())
        );

        List<Shift> shifts = new ArrayList<>();
        LocalDateTime shiftStart = LocalDateTime.of(2026, 7, 16, 8, 30);
        LocalDateTime shiftEnd = LocalDateTime.of(2026, 7, 16, 17, 30);

        for (int i = 0; i < 14; i++) {
            shifts.add(new Shift("shift-" + i, shiftStart, shiftEnd, "Main Office", "Practice Manager", null));
        }

        return new EmployeeSchedule(employees, shifts);
    }

    private long getUsedHeapMB() {
        MemoryUsage heapUsage = memoryMXBean.getHeapMemoryUsage();
        return heapUsage.getUsed() / 1024 / 1024;
    }

    private void forceGC() {
        // Run GC multiple times to increase chance of full collection
        for (int i = 0; i < 3; i++) {
            System.gc();
            try {
                Thread.sleep(100);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        // Give GC time to complete
        try {
            Thread.sleep(500);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
